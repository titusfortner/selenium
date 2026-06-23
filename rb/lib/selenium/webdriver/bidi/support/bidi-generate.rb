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

  # Local constant for a domain-scoped type: "script.LocalValue" -> "LocalValue".
  # The first letter is capitalized so a lower-cased spec name (e.g.
  # "permissions.setPermission") still yields a valid Ruby constant.
  def self.type_class_name(type_name)
    type_name.split('.', 2).last.sub(/\A[a-z]/, &:upcase)
  end

  # Protocol-relative class path: "script.LocalValue" -> "Script::LocalValue".
  def self.type_ruby_path(type_name)
    domain = type_name.split('.', 2).first
    "#{snake_to_class_name(camel_to_snake(domain))}::#{type_class_name(type_name)}"
  end

  # Source literal for a discriminator/const value (string, boolean, or number).
  def self.ruby_literal(value)
    value.is_a?(String) ? "'#{value}'" : value.to_s
  end

  # Append underscore to avoid clashing with Ruby reserved keywords.
  def self.safe_method_name(name)
    RUBY_RESERVED.include?(name) ? "#{name}_" : name
  end

  # Object/Data methods a Data member name would shadow (breaking value semantics
  # or reflection), e.g. a "method" field overriding Object#method.
  RESERVED_FIELD_NAMES = (RUBY_RESERVED + %w[method hash class send dup clone freeze inspect
                                             to_h to_s members with deconstruct deconstruct_keys
                                             object_id tap itself then display
                                             extensible extensions]).freeze

  # Append underscore to a field name that would shadow a core method; the wire
  # name is unaffected, only the Ruby reader is renamed.
  def self.safe_field_name(name)
    RESERVED_FIELD_NAMES.include?(name) ? "#{name}_" : name
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
  # result_ref is the Protocol-relative class path the response parses into
  # (e.g. "BrowsingContext::NavigateResult"), or nil to return the raw hash.
  Command = Struct.new(:wire_name, :method_name, :params, :passthrough, :result_ref, keyword_init: true) do
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

  # -- Structured-type IR (Phase 2) --

  # ref is the Protocol-relative class path for a nested structured field (nil
  # for a scalar/opaque field); list wraps it in an array.
  FieldIR = Struct.new(:ruby_name, :wire, :required, :nullable, :ref, :list, keyword_init: true) do
    # A `Data.define` spec entry: `name: 'wire'` shorthand, or
    # `name: {wire:, …}` when the field carries wire facts beyond its name.
    # (required is baked in the schema but not yet enforced at runtime — Phase 4.)
    def spec_entry
      meta = []
      meta << 'nullable: true' if nullable
      meta << "ref: '#{ref}'" if ref
      meta << 'list: true' if list
      return "#{ruby_name}: '#{wire}'" if meta.empty?

      "#{ruby_name}: {wire: '#{wire}', #{meta.join(', ')}}"
    end
  end

  # A generated immutable value type (a Data.define(...) class). discriminator is
  # the baked variant tag {ruby_name:, wire:, value:} (a fixed member) or nil.
  TypeClass = Struct.new(:ruby_name, :fields, :discriminator, :extensible, keyword_init: true) do
    def union? = false

    # Keyword arguments for `Data.define(...)`: the fixed discriminator member
    # first, then the fields, then the extensible flag.
    def define_args
      entries = []
      entries << discriminator_entry if discriminator
      entries.concat(fields.map(&:spec_entry))
      entries << 'extensible: true' if extensible
      entries.join(', ')
    end

    def discriminator_entry
      literal = BiDiGenerate.ruby_literal(discriminator[:value])
      if discriminator[:wire] == discriminator[:ruby_name].to_s
        "#{discriminator[:ruby_name]}: {fixed: #{literal}}"
      else
        "#{discriminator[:ruby_name]}: {wire: '#{discriminator[:wire]}', fixed: #{literal}}"
      end
    end
  end

  # mode is :value (matched by discriminator), :fallback (the no-tag variant), or
  # :presence (selected when its required wire keys are all present).
  VariantIR = Struct.new(:mode, :value, :ref, :requires, keyword_init: true)

  # A generated discriminated union (< Protocol::Union).
  UnionClass = Struct.new(:ruby_name, :discriminator_wire, :variants, keyword_init: true) do
    def union? = true
    def value_variants = variants.select { |v| v.mode == :value }
    def presence_variants = variants.select { |v| v.mode == :presence }
    def fallback_variant = variants.find { |v| v.mode == :fallback }
  end

  Module = Struct.new(:name, :ruby_class, :filename, :commands, :events, :enums, :types, keyword_init: true)

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

    # Structured value classes (records + discriminated unions) declared under
    # "<domain>." Empty records are projector artifacts with nothing to carry, so
    # they stay opaque hashes; only non-empty records and unions become classes.
    def types_for(domain)
      prefix = "#{domain}."
      @types.filter_map do |name, type|
        next unless name.start_with?(prefix)

        case type['kind']
        when 'record' then record_class(name, type) unless type['fields'].empty?
        when 'union' then union_class(name)
        when 'alias' then union_class(name) if type['type'].key?('union')
        end
      end
    end

    # The Protocol-relative class path a command result parses into, or nil when
    # it is non-structured (or a bare list, returned raw).
    def structured_ref(name)
      resolved = resolve_ref(name)
      resolved[:list] ? nil : resolved[:ref]
    end

    private

    def domain_path(name)
      name.include?('.') ? BiDiGenerate.type_ruby_path(name) : nil
    end

    # Resolves a named ref to {ref:, list:, nullable:}, transparently following
    # aliases — including alias-to-list — so an element type behind an alias
    # (e.g. script.ListLocalValue -> [script.LocalValue]) is preserved. ref is the
    # Protocol-relative path of the nested structured type, or nil for a scalar /
    # enum / empty record / global envelope type (all opaque). seen guards against
    # cyclic ref-aliases.
    def resolve_ref(name, nullable = false, seen = {})
      miss = {ref: nil, list: false, nullable: nullable}
      return miss if name.nil? || seen[name]

      seen[name] = true
      type = @types[name]
      return miss unless type

      case type['kind']
      when 'record' then {ref: type['fields'].empty? ? nil : domain_path(name), list: false, nullable: nullable}
      when 'union' then {ref: domain_path(name), list: false, nullable: nullable}
      when 'alias' then resolve_alias(name, type['type'], nullable, seen)
      else miss
      end
    end

    def resolve_alias(name, inner, nullable, seen)
      return {ref: domain_path(name), list: false, nullable: nullable} if inner.key?('union')
      return resolve_ref(inner['ref'], nullable, seen) if inner.key?('ref')

      if inner.key?('list')
        element = resolve_node(inner['list'])
        return {ref: element[:ref], list: true, nullable: nullable}
      end

      {ref: nil, list: false, nullable: nullable}
    end

    def record_class(name, type)
      const = type['fields'].find { |f| f['type'].key?('const') }
      discriminator = const && {ruby_name: BiDiGenerate.safe_field_name(BiDiGenerate.camel_to_snake(const['name'])),
                                wire: const['wire'], value: const['type']['const']}
      fields = type['fields'].reject { |f| f['type'].key?('const') }.map { |f| field_ir(f) }
      TypeClass.new(ruby_name: BiDiGenerate.type_class_name(name), fields: fields,
                    discriminator: discriminator, extensible: type['extensible'] ? true : false)
    end

    def field_ir(field)
      resolved = resolve_node(field['type'])
      ruby_name = BiDiGenerate.safe_field_name(BiDiGenerate.camel_to_snake(field['name']))
      FieldIR.new(ruby_name: ruby_name, wire: field['wire'],
                  required: field['required'], nullable: resolved[:nullable],
                  ref: resolved[:ref], list: resolved[:list])
    end

    def resolve_node(node)
      nullable = node['nullable'] ? true : false
      return {ref: resolve_node(node['list'])[:ref], list: true, nullable: nullable} if node.key?('list')
      return resolve_ref(node['ref'], nullable) if node.key?('ref')

      {ref: nil, list: false, nullable: nullable}
    end

    def union_class(name)
      leaves = expand_variants(name)
      wires = leaves.filter_map { |l| l[:const]&.fetch(:wire) }.uniq
      no_tag = leaves.reject { |l| l[:const] }
      variants = leaves.map { |leaf| variant_ir(leaf, only_fallback: no_tag.size == 1) }
      UnionClass.new(ruby_name: BiDiGenerate.type_class_name(name),
                     discriminator_wire: wires.size == 1 ? wires.first : nil, variants: variants)
    end

    def variant_ir(leaf, only_fallback:)
      path = BiDiGenerate.type_ruby_path(leaf[:name])
      if leaf[:const]
        VariantIR.new(mode: :value, value: leaf[:const][:value], ref: path, requires: nil)
      elsif only_fallback
        VariantIR.new(mode: :fallback, value: nil, ref: path, requires: nil)
      else
        VariantIR.new(mode: :presence, value: nil, ref: path, requires: leaf[:requires])
      end
    end

    # Recursively flattens a union (and any union-typed variants) into leaf record
    # variants, each tagged with its const discriminator (if any) and the wire
    # keys that identify it by presence.
    def expand_variants(name)
      variant_names(name).flat_map do |vn|
        union?(vn) ? expand_variants(vn) : [leaf_info(vn)]
      end
    end

    def variant_names(name)
      type = @types[name]
      return type['variants'] if type['kind'] == 'union'

      type['type']['union'].filter_map { |arm| arm['ref'] }
    end

    def union?(name)
      type = @types[name]
      type && (type['kind'] == 'union' || (type['kind'] == 'alias' && type['type'].key?('union')))
    end

    def leaf_info(name)
      type = @types[name]
      fields = type['kind'] == 'record' ? type['fields'] : []
      const = fields.find { |f| f['type'].key?('const') }
      requires = fields.select { |f| f['required'] && !f['type'].key?('const') }.map { |f| f['wire'] }
      {name: name, const: const && {wire: const['wire'], value: const['type']['const']}, requires: requires}
    end

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
          passthrough: params.nil?,
          result_ref: cmd['result'] && schema.structured_ref(cmd['result']['ref'])
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
        enums: schema.enums_for(domain),
        types: schema.types_for(domain)
      )
    end
  end

  # -- Coverage (Phase 2) --

  # Classifies every schema type into one conscious category and validates every
  # type node against the known grammar. An unrecognized kind or node shape
  # raises, so a new spec construct surfaces as a build failure instead of being
  # silently dropped — the build-side complement to the JS projector's cddl2ts
  # fidelity gate. Categories are also what later passes key structured codegen
  # off of (union dispatch, parsed results, …); for now they prove 100% of the
  # surface is accounted for.
  class Coverage
    PRIMITIVES = %w[string number integer boolean null unknown].freeze

    class Unrecognized < StandardError; end

    Report = Struct.new(:categories, :total, keyword_init: true) do
      def summary
        "#{total} types (#{categories.sort.map { |k, v| "#{k}:#{v}" }.join(' ')})"
      end
    end

    def initialize(schema)
      @types = schema['types']
      @commands = schema['commands']
      @events = schema['events']
    end

    # Validates the whole schema (raising on anything unrecognized) and returns
    # a Report tallying each type by category.
    def check!
      categories = Hash.new(0)
      @types.each do |name, type|
        categories[classify(name, type)] += 1
        validate_typedef(name, type)
      end
      (@commands + @events).each { |entry| validate_entry(entry) }
      Report.new(categories: categories, total: @types.size)
    end

    private

    def classify(name, type)
      case type['kind']
      when 'enum' then :enum
      when 'union' then :union
      when 'record' then classify_record(type)
      when 'alias' then classify_alias(type['type'])
      else raise Unrecognized, "type kind #{type['kind'].inspect} for #{name}"
      end
    end

    def classify_record(type)
      return :extensible_record if type['extensible']
      return :map_record if type['map']
      return :scalar_record if type['fields'].all? { |f| scalar_node?(f['type']) }

      :nested_record
    end

    def classify_alias(node)
      return :union_alias if node.key?('union')
      return :ref_alias if node.key?('ref')

      :scalar_alias
    end

    def scalar_node?(node)
      node.key?('primitive') || node.key?('const') || node.key?('enum')
    end

    def validate_typedef(name, type)
      case type['kind']
      when 'enum' then raise_unless(type['values'].is_a?(Array), "enum values for #{name}")
      when 'union' then type['variants'].each { |v| resolve!(v, name) }
      when 'record'
        type['fields'].each { |f| validate_field(f, name) }
        validate_node(type['map'], name) if type['map']
      when 'alias' then validate_node(type['type'], name)
      end
    end

    def validate_field(field, owner)
      raise_unless(field.keys.sort == %w[name required type wire], "field keys #{field.keys} in #{owner}")
      validate_node(field['type'], owner)
    end

    # Recursively validates a nested type node against the known grammar.
    def validate_node(node, owner)
      raise_unless(node.is_a?(Hash), "type node #{node.inspect} in #{owner}")
      keys = node.keys - ['nullable']
      case keys
      when ['ref'] then resolve!(node['ref'], owner)
      when ['primitive'] then raise_unless(PRIMITIVES.include?(node['primitive']), "primitive #{node['primitive']} in #{owner}")
      when ['const'] then nil
      when ['enum'] then raise_unless(node['enum'].is_a?(Array), "inline enum in #{owner}")
      when ['list'] then validate_node(node['list'], owner)
      when ['union'] then node['union'].each { |n| validate_node(n, owner) }
      when ['record'] then node['record'].each { |f| validate_field(f, owner) }
      else raise Unrecognized, "type node #{node.keys.sort} in #{owner}"
      end
    end

    def validate_entry(entry)
      %w[params result].each do |slot|
        ref = entry[slot]
        resolve!(ref['ref'], entry['method']) if ref&.key?('ref')
      end
    end

    def resolve!(ref, owner)
      raise_unless(@types.key?(ref), "dangling ref #{ref.inspect} in #{owner}")
    end

    def raise_unless(condition, what)
      raise Unrecognized, "unrecognized/invalid #{what}" unless condition
    end
  end

  # -- Rendering --

  def self.render(mod, template_path)
    ERB.new(File.read(template_path), trim_mode: '-').result(binding)
  end

  # -- Entry point --

  def self.call(schema_path, output_dir)
    raw = load_json(schema_path)
    warn "bidi-generate: coverage #{Coverage.new(raw).check!.summary}"
    schema = Schema.new(raw)
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
