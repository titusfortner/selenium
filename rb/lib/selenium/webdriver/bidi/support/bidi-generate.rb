# frozen_string_literal: true

# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'json'
require 'erb'
require 'fileutils'

# Generates Ruby WebDriver BiDi protocol modules from the shared, binding-neutral
# BiDi schema produced by the JavaScript generator (see PR #17700):
#   //javascript/selenium-webdriver:create-bidi-src_schema -> bidi-schema.json
#
# The schema is already normalized (inline enums hoisted, unions canonicalized,
# group composition flattened, wire names and nullability preserved verbatim), so
# this generator is a straight projection into Ruby with no CDDL interpretation.
#
# Invoked via `bazel run //rb/lib/selenium/webdriver:bidi-generate`. Bazel passes
# the schema path (resolved through runfiles) plus the workspace-relative output
# directory as ARGV. Can also be run directly:
#   ruby bidi-generate.rb schema.json output/dir
module BiDiGenerate
  # Ruby keywords that cannot be used as method names unquoted.
  RUBY_RESERVED = %w[begin end rescue ensure raise return yield if unless while until for do
                     case when then class module def].freeze

  def self.camel_to_snake(str)
    str
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase
  end

  def self.snake_to_class_name(snake)
    snake.split('_').map(&:capitalize).join
  end

  # Append underscore to avoid clashing with Ruby reserved keywords.
  def self.safe_method_name(name)
    RUBY_RESERVED.include?(name) ? "#{name}_" : name
  end

  # SCREAMING_SNAKE constant name for an enum, matching the EVENTS map style
  # (ReadinessState → READINESS_STATE).
  def self.screaming_snake(camel)
    camel_to_snake(camel).upcase
  end

  # snake_case hash key for an enum value. Preserves camelCase word boundaries
  # (beforeRequestSent → before_request_sent), maps a leading minus to "neg_"
  # (-0 → neg_0, -Infinity → neg_infinity), and collapses other punctuation
  # (dedicated-worker → dedicated_worker).
  def self.enum_key(value)
    camel_to_snake(value.to_s)
      .sub(/\A-/, 'neg_')
      .gsub(/[^a-z0-9]+/, '_')
      .gsub(/\A_+|_+\z/, '')
  end

  # -- IR --

  # ruby_name is the snake_case keyword argument; wire_name is the exact key the
  # protocol expects (baked verbatim from the schema, no runtime conversion).
  Param = Struct.new(:ruby_name, :wire_name, :required, keyword_init: true) do
    def sig_part
      required ? "#{ruby_name}:" : "#{ruby_name}: nil"
    end
  end

  # passthrough commands have params the schema models as a union/alias (not a
  # flat record), which Phase 1 keyword args cannot express. They forward raw
  # keyword args until structured union dispatch lands (Phase 2).
  Command = Struct.new(:wire_name, :method_name, :params, :passthrough, keyword_init: true) do
    def required_params = params.select(&:required)
    def optional_params = params.reject(&:required)

    def signature
      (required_params.map(&:sig_part) + optional_params.map(&:sig_part)).join(', ')
    end

    # context: context, promptUnload: prompt_unload
    def send_args_str
      params.map { |p| "#{p.wire_name}: #{p.ruby_name}" }.join(', ')
    end
  end

  Event = Struct.new(:wire_name, :event_name, keyword_init: true)

  # constant_name is the SCREAMING_SNAKE hash name; entries are [symbol_key, wire_value] pairs.
  Enum = Struct.new(:constant_name, :entries, keyword_init: true)

  Module = Struct.new(:name, :ruby_class, :filename, :commands, :events, :enums, keyword_init: true)

  # -- Schema projection --

  class Schema
    def initialize(schema)
      @types = schema['types']
      @commands = schema['commands']
      @events = schema['events']
    end

    # Domains that carry a command or event each become one generated module.
    def domains
      (@commands + @events).map { |entry| entry['domain'] }.uniq
    end

    def commands_for(domain)
      @commands.select { |c| c['domain'] == domain }
    end

    def events_for(domain)
      @events.select { |e| e['domain'] == domain }
    end

    # Flat params for a command: the record's fields, or — for a union of
    # records — the merged superset of variant fields. Returns [] for commands
    # with no params, or nil when params can't be flattened (alias, or a union
    # whose variants aren't all records) so the caller forwards verbatim.
    def params_for(params_ref)
      return [] unless params_ref

      type = @types[params_ref['ref']]
      return nil unless type

      case type['kind']
      when 'record' then record_params(type['fields'])
      when 'union' then union_params(type)
      end
    end

    # Enum types declared under "<domain>." become nested constant modules.
    def enums_for(domain)
      @types.filter_map do |name, type|
        next unless type['kind'] == 'enum'
        next unless name.start_with?("#{domain}.")

        entries = type['values'].map { |v| [BiDiGenerate.enum_key(v), v.to_s] }
        Enum.new(constant_name: BiDiGenerate.screaming_snake(name.sub("#{domain}.", '')), entries: entries)
      end
    end

    private

    def record_params(fields)
      fields.map do |field|
        Param.new(
          ruby_name: BiDiGenerate.camel_to_snake(field['name']),
          wire_name: field['wire'],
          required: field['required']
        )
      end
    end

    # Merge a union's record variants into one flat param list. A field is only
    # required when every variant declares it required; variant-specific fields
    # become optional. Which-variant validation is deferred (Phase 2 union
    # dispatch) — the server still rejects invalid combinations meanwhile.
    def union_params(type)
      variants = type['variants'].map { |ref| @types[ref] }
      return nil unless variants.all? { |v| v && v['kind'] == 'record' }

      variant_fields = variants.map { |v| v['fields'] }
      ordered_wires = variant_fields.flatten.map { |f| f['wire'] }.uniq

      ordered_wires.map do |wire|
        field = variant_fields.flatten.find { |f| f['wire'] == wire }
        required = variant_fields.all? { |fields| fields.any? { |f| f['wire'] == wire && f['required'] } }
        Param.new(
          ruby_name: BiDiGenerate.camel_to_snake(field['name']),
          wire_name: wire,
          required: required
        )
      end
    end
  end

  def self.build_ir(schema)
    schema.domains.map do |domain|
      snake = camel_to_snake(domain)

      commands = schema.commands_for(domain).map do |cmd|
        params = schema.params_for(cmd['params'])
        Command.new(
          wire_name: cmd['method'],
          method_name: safe_method_name(camel_to_snake(cmd['name'])),
          params: params || [],
          passthrough: params.nil?
        )
      end

      events = schema.events_for(domain).map do |ev|
        Event.new(wire_name: ev['method'], event_name: camel_to_snake(ev['name']))
      end

      Module.new(
        name: domain,
        ruby_class: snake_to_class_name(snake),
        filename: snake,
        commands: commands,
        events: events,
        enums: schema.enums_for(domain)
      )
    end
  end

  # -- Rendering --

  def self.render(mod, template_path)
    ERB.new(File.read(template_path), trim_mode: '-').result(binding)
  end

  # -- Entry point --

  def self.call(schema_path, output_dir)
    schema = Schema.new(load_json(schema_path))
    modules = build_ir(schema)

    target = File.join(workspace_root, output_dir)
    FileUtils.mkdir_p(target)

    tmpl = File.join(File.dirname(__FILE__), 'templates', 'module.rb.erb')
    modules.each do |mod|
      path = File.join(target, "#{mod.filename}.rb")
      File.write(path, render(mod, tmpl))
      warn "bidi-generate: wrote #{path}"
    end
  end

  private_class_method def self.load_json(path)
    resolved = File.exist?(path) ? path : File.join(Dir.pwd, path)
    JSON.parse(File.read(resolved))
  end

  private_class_method def self.workspace_root
    ENV['BUILD_WORKSPACE_DIRECTORY'] || Dir.pwd
  end
end

BiDiGenerate.call(*ARGV) if $PROGRAM_NAME == __FILE__
