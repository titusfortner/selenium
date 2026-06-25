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
  # Companion to the generated `@api private` tags: the page explaining why the BiDi
  # implementation layer is internal and what higher-level API to use instead (see #17628).
  BIDI_DOC_URL = 'https://www.selenium.dev/documentation/warnings/bidi-implementation/'

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
    return 'nil' if value.nil?

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

  # Makes an RBS type admit nil, idempotently (an already-nilable or opaque type is
  # left as-is). Used both for nullable fields and for optional params, where passing
  # nil is the runtime equivalent of omitting the argument.
  def self.rbs_nilable(type)
    return type if type == 'untyped' || type == 'nil' || type.end_with?('?')

    "#{type}?"
  end

  # Domain-qualified path to an enum's frozen hash constant
  # ("browsingContext.ReadinessState" → "BrowsingContext::READINESS_STATE"), so a
  # generated command method can reference it for an outbound membership check.
  def self.enum_const_path(type_name)
    domain, local = type_name.split('.', 2)
    "#{snake_to_class_name(camel_to_snake(domain))}::#{screaming_snake(local)}"
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
  # protocol expects (baked verbatim from the schema, no runtime conversion). enum is
  # the allowed-values constant path for an enum-typed param (nil otherwise).
  Param = Struct.new(:ruby_name, :wire_name, :required, :enum, :rbs, keyword_init: true) do
    # Optionals default to UNSET (omitted), so an explicit nil can still reach a
    # nullable field as wire null.
    def sig_part
      required ? "#{ruby_name}:" : "#{ruby_name}: UNSET"
    end

    def enum_check
      "Enum.check!('#{wire_name}', #{ruby_name}, #{enum})" if enum
    end

    # An RBS keyword parameter carrying the param's value type. A required param is its
    # bare type; an optional one is prefixed `?` and admits nil, since passing nil is the
    # runtime equivalent of omitting it (a non-nullable field's nil is dropped on the wire).
    def rbs_part
      type = rbs || 'untyped'
      required ? "#{ruby_name}: #{type}" : "?#{ruby_name}: #{BiDiGenerate.rbs_nilable(type)}"
    end
  end

  # passthrough commands have params the schema models as an alias (not a flat record
  # or union of records), which keyword args can't express; they forward raw kwargs.
  # params_class is the Parameters class the named args construct (nil for
  # passthrough/none); union_params picks its variant via `.build` rather than `.new`.
  # result_ref is the Protocol-relative result class path, or nil to return the raw hash.
  Command = Struct.new(:wire_name, :method_name, :params, :passthrough, :result_ref, :params_class,
                       :union_params, keyword_init: true) do
    def required_params = params.select(&:required)
    def optional_params = params.reject(&:required)
    def enum_checks = params.filter_map(&:enum_check)

    def signature
      (required_params.map(&:sig_part) + optional_params.map(&:sig_part)).join(', ')
    end

    # The RBS method signature `(params) -> return`. A passthrough forwards `**untyped`;
    # the return is the typed result class when the command parses one, else `untyped`.
    def rbs_signature
      return '(**untyped) -> untyped' if passthrough

      "(#{rbs_params}) -> #{rbs_return}"
    end

    def rbs_params
      (required_params.map(&:rbs_part) + optional_params.map(&:rbs_part)).join(', ')
    end

    def rbs_return
      result_ref ? "::Selenium::WebDriver::BiDi::Protocol::#{result_ref}" : 'untyped'
    end

    # `@transport.execute(method[, params][, result_type])` — params is the
    # constructed Parameters object or a passthrough `**params` hash; result_type is
    # the trailing positional when the result is structured.
    def execute_call
      arg = passthrough ? 'params' : params_arg
      parts = ["'#{wire_name}'"]
      if result_ref
        parts << (arg || 'nil')
        parts << "Protocol.const_get('#{result_ref}')"
      elsif arg
        parts << arg
      end
      "@transport.execute(#{parts.join(', ')})"
    end

    def params_arg
      return nil if params.empty?
      # Without an emitted Parameters class (a non-record/union flattened param),
      # forward a flat wire-keyed hash. A record builds its Parameters object; a
      # union dispatches to the matching variant via `.build` (its typed as_json
      # emits explicit null where a flat hash through Transport could not).
      return "{#{params.map { |p| "#{p.wire_name}: #{p.ruby_name}" }.join(', ')}}" unless params_class

      ctor = union_params ? 'build' : 'new'
      "#{params_class}.#{ctor}(#{params.map { |p| "#{p.ruby_name}: #{p.ruby_name}" }.join(', ')})"
    end
  end

  Event = Struct.new(:wire_name, :event_name, keyword_init: true)

  # constant_name is the SCREAMING_SNAKE hash name; pairs are [symbol_key, wire_value] tuples.
  Enum = Struct.new(:constant_name, :pairs, keyword_init: true)

  # -- Structured-type IR (Phase 2) --

  # ref is the Protocol-relative class path for a nested structured field (nil
  # for a scalar/opaque field); list wraps it in an array. json_key is the exact
  # JSON payload key (the schema's `wire` name, baked verbatim).
  FieldIR = Struct.new(:ruby_name, :json_key, :required, :nullable, :ref, :list, :enum, :rbs, keyword_init: true) do
    # A `Data.define` spec entry: `name: 'jsonKey'` shorthand, or
    # `name: {json_key:, …}` when the field carries JSON facts beyond its name.
    # enum carries the allowed-values constant path, validated at construction.
    def spec_entry
      meta = []
      meta << 'nullable: true' if nullable
      meta << "ref: '#{ref}'" if ref
      meta << 'list: true' if list
      meta << "enum: '#{enum}'" if enum
      return "#{ruby_name}: '#{json_key}'" if meta.empty?

      "#{ruby_name}: {json_key: '#{json_key}', #{meta.join(', ')}}"
    end

    # The `self.new` keyword for this field — a user-supplied input carrying the field's
    # value type. An optional field is prefixed `?` and admits nil (nil omits it, same as
    # the command-param path); a required field is its bare type.
    def rbs_arg
      required ? "#{ruby_name}: #{rbs}" : "?#{ruby_name}: #{BiDiGenerate.rbs_nilable(rbs)}"
    end

    # The `attr_reader` type. A present value is `rbs`; an omitted optional reads back
    # the UNSET sentinel, which a value type can't capture, so optionals stay `untyped`.
    def rbs_reader
      "#{ruby_name}: #{required ? rbs : 'untyped'}"
    end
  end

  # A generated immutable value type (a Data.define(...) class). discriminator is the
  # baked variant tag {ruby_name:, wire:, value:} or nil; schema_name/synthetic/owner/
  # nested drive owner-nesting (see nest_synthetic).
  TypeClass = Struct.new(:ruby_name, :fields, :discriminator, :extensible,
                         :schema_name, :synthetic, :owner, :label, :nested, keyword_init: true) do
    def union? = false
    def nested_types = nested || []

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
        "#{discriminator[:ruby_name]}: {json_key: '#{discriminator[:wire]}', fixed: #{literal}}"
      end
    end

    # Every Data member gets a typed `attr_reader`: the baked discriminator (untyped),
    # each field (typed when required; UNSET-bearing optionals stay untyped), then the
    # extensible passthrough.
    def rbs_readers
      readers = []
      readers << "#{discriminator[:ruby_name]}: untyped" if discriminator
      readers.concat(fields.map(&:rbs_reader))
      readers << 'extensions: Hash[String, untyped]' if extensible
      readers
    end

    # The keyword arguments `self.new` accepts: each constructable field with its value
    # type, plus the optional extensions bag. The fixed discriminator is baked, so its
    # value is ignored — but the lenient `**kwargs` constructor still accepts it (and a
    # command method passes it through), so it is advertised as an optional keyword.
    def rbs_new_args
      parts = []
      parts << "?#{discriminator[:ruby_name]}: untyped" if discriminator
      parts.concat(fields.map(&:rbs_arg))
      parts << '?extensions: untyped' if extensible
      parts.join(', ')
    end
  end

  # mode is :value (matched by discriminator), :fallback (the no-tag variant), or
  # :presence (selected when its required wire keys are all present).
  VariantIR = Struct.new(:mode, :value, :ref, :requires, keyword_init: true)

  # A generated discriminated union (< BiDi::Union, resolved by lexical scope).
  # nested holds its synthetic variant records (see nest_synthetic).
  UnionClass = Struct.new(:ruby_name, :discriminator_wire, :variants, :schema_name, :nested, keyword_init: true) do
    def union? = true
    def value_variants = variants.select { |v| v.mode == :value }
    def presence_variants = variants.select { |v| v.mode == :presence }
    def fallback_variant = variants.find { |v| v.mode == :fallback }
    def nested_types = nested || []
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

    def type_kind(ref)
      @types[ref]&.fetch('kind', nil)
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
      when 'union' then union_params(type, params_ref['ref'])
      end
    end

    # Enum types declared under "<domain>." become nested constant modules.
    def enums_for(domain)
      @types.filter_map do |name, type|
        next unless type['kind'] == 'enum'
        next unless name.start_with?("#{domain}.")

        pairs = type['values'].map { |v| [BiDiGenerate.enum_key(v), v.to_s] }
        Enum.new(constant_name: BiDiGenerate.screaming_snake(name.sub("#{domain}.", '')), pairs: pairs)
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
      name.include?('.') ? ruby_path(name) : nil
    end

    # Class path, nesting a synthetic type under its owner as `Owner::Label` so a ref
    # resolves to the same nested constant the type is emitted as.
    def ruby_path(name)
      type = @types[name]
      return BiDiGenerate.type_ruby_path(name) unless type && type['synthetic']

      "#{ruby_path(type['owner'])}::#{type['label']}"
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
                    discriminator: discriminator, extensible: type['extensible'] ? true : false,
                    schema_name: name, synthetic: type['synthetic'] ? true : false,
                    owner: type['owner'], label: type['label'])
    end

    def field_ir(field)
      resolved = resolve_node(field['type'])
      ruby_name = BiDiGenerate.safe_field_name(BiDiGenerate.camel_to_snake(field['name']))
      FieldIR.new(ruby_name: ruby_name, json_key: field['wire'],
                  required: field['required'], nullable: resolved[:nullable],
                  ref: resolved[:ref], list: resolved[:list], enum: enum_const(field['type']),
                  rbs: rbs_type(field['type']))
    end

    def resolve_node(node)
      nullable = node['nullable'] ? true : false
      return {ref: resolve_node(node['list'])[:ref], list: true, nullable: nullable} if node.key?('list')
      return resolve_ref(node['ref'], nullable) if node.key?('ref')

      {ref: nil, list: false, nullable: nullable}
    end

    def union_class(name)
      type = @types[name]
      # A first-class union carries the schema's authoritative dispatch `selector`
      # (derived spec-faithfully, including null discriminators and the spec's choice
      # order); consume it rather than re-deriving and silently depending on emit
      # order. An alias-to-union (only input.Origin) has no selector — its const-string
      # arms aren't first-class types — so it keeps the structural re-derivation.
      type['kind'] == 'union' ? union_from_selector(name, type['selector']) : union_from_alias(name)
    end

    # Map a union `selector` to dispatch variants the template renders:
    #   { by, variants, default? } -> a discriminator table (value => ref), `default`
    #     as the fallback (it may itself be a union, which finishes the dispatch).
    #   { ordered: [{ ref, requires }] } -> presence rules in the spec's choice order.
    #   { correlated: true } -> resolved by request id, not the payload, so no payload
    #     dispatch. Unreachable here: every correlated union is a top-level result
    #     grouping, never domain-scoped, so it is never emitted as a class.
    def union_from_selector(name, selector)
      # A correlated union is resolved by request id, never the payload, so it carries
      # no dispatch — it must never be emitted (every one is a top-level result
      # grouping). Fail loudly if a future schema makes one domain-scoped rather than
      # emit a Union whose every parse would raise.
      if selector['correlated']
        raise "correlated union #{name} must not be emitted (resolved by request id, not payload)"
      end

      variants = selector['by'] ? discriminated_variants(selector) : ordered_variants(selector)
      raise "union #{name} selector yielded no dispatch variants" if variants.empty?

      UnionClass.new(ruby_name: BiDiGenerate.type_class_name(name),
                     discriminator_wire: selector['by'], variants: variants, schema_name: name)
    end

    def discriminated_variants(selector)
      variants = selector['variants'].map do |variant|
        VariantIR.new(mode: :value, value: variant['value'], ref: ruby_path(variant['ref']), requires: nil)
      end
      return variants unless selector['default']

      variants << VariantIR.new(mode: :fallback, value: nil, ref: ruby_path(selector['default']), requires: nil)
    end

    def ordered_variants(selector)
      (selector['ordered'] || []).map do |arm|
        VariantIR.new(mode: :presence, value: nil, ref: ruby_path(arm['ref']), requires: arm['requires'])
      end
    end

    # The sole alias-union is input.Origin ("viewport" | "pointer" | ElementOrigin): a
    # scalar-or-object union the object-payload selector model doesn't cover, so the
    # projector leaves it an alias with no selector. Its object arm(s) carry a const
    # discriminator; the bare-string arms need no dispatch (Union.from_json returns a
    # non-Hash payload unchanged). So dispatch the ref arms by their const tag.
    def union_from_alias(name)
      consts = @types[name]['type']['union'].filter_map { |arm| arm['ref'] }.to_h do |ref|
        const = @types[ref]['fields'].find { |f| f['type'].key?('const') }
        const || raise("alias-union #{name} arm #{ref} has no const discriminator to dispatch on")
        [ref, const]
      end
      variants = consts.map do |ref, const|
        VariantIR.new(mode: :value, value: const['type']['const'], ref: ruby_path(ref), requires: nil)
      end
      UnionClass.new(ruby_name: BiDiGenerate.type_class_name(name),
                     discriminator_wire: consts.values.first['wire'], variants: variants, schema_name: name)
    end

    def record_params(fields)
      fields.map do |field|
        Param.new(
          ruby_name: BiDiGenerate.safe_field_name(BiDiGenerate.camel_to_snake(field['name'])),
          wire_name: field['wire'],
          required: field['required'],
          enum: enum_const(field['type']),
          rbs: rbs_type(field['type'])
        )
      end
    end

    # Projects a schema type node to an RBS type. Structured refs resolve to their
    # absolute Protocol class path, enums and scalar aliases to their underlying scalar,
    # lists to `Array[...]`, and a nullable node gains a trailing `?`. Anything the
    # generator does not model as a value type stays `untyped`.
    PRIMITIVE_RBS = {
      'string' => 'String', 'number' => 'Numeric', 'integer' => 'Integer',
      'boolean' => 'bool', 'null' => 'nil', 'unknown' => 'untyped'
    }.freeze

    def rbs_type(node)
      base = rbs_base(node)
      node['nullable'] ? BiDiGenerate.rbs_nilable(base) : base
    end

    def rbs_base(node)
      return "Array[#{rbs_type(node['list'])}]" if node.key?('list')
      return rbs_ref_type(node['ref']) if node.key?('ref')
      return PRIMITIVE_RBS.fetch(node['primitive'], 'untyped') if node.key?('primitive')
      return rbs_const(node['const']) if node.key?('const')

      'untyped'
    end

    def rbs_const(value)
      case value
      when true, false then 'bool'
      when ::String then 'String'
      when ::Numeric then 'Numeric'
      else 'untyped'
      end
    end

    # Resolves a ref to its RBS type, following aliases as resolve_ref does: a value
    # type yields its class path, an enum/scalar its scalar, a list its element array.
    def rbs_ref_type(ref, seen = {})
      return 'untyped' if ref.nil? || seen[ref]

      seen[ref] = true
      type = @types[ref]
      return 'untyped' unless type

      case type['kind']
      when 'record' then type['fields'].empty? ? 'untyped' : rbs_abs(ruby_path(ref))
      when 'union' then rbs_abs(ruby_path(ref))
      when 'enum' then 'String'
      when 'alias' then rbs_alias_type(ref, type['type'], seen)
      end
    end

    def rbs_alias_type(ref, inner, seen)
      return rbs_abs(ruby_path(ref)) if inner.key?('union')
      return rbs_ref_type(inner['ref'], seen) if inner.key?('ref')

      rbs_base(inner)
    end

    def rbs_abs(path)
      "::Selenium::WebDriver::BiDi::Protocol::#{path}"
    end

    # The allowed-values constant path when a field (or a list's element) is an enum
    # type, else nil. Union command-params skip this (their merged superset can blur a
    # discriminator's const vs enum); only flat record params get the outbound check.
    def enum_const(field_type)
      ref = field_type['ref'] || field_type.dig('list', 'ref')
      return unless ref && @types[ref] && @types[ref]['kind'] == 'enum'

      BiDiGenerate.enum_const_path(ref)
    end

    # Merge a union's record variants into one flat param list for the command
    # signature. A field is only required when every variant declares it required;
    # variant-specific fields become optional. The command body dispatches these
    # kwargs to the matching variant via `Union.build`, whose typed `as_json` handles
    # null-vs-absent — so no nullable allowlist is needed.
    def union_params(type, ref = nil)
      variants = type['variants'].map { |variant_ref| @types[variant_ref] }
      return nil unless variants.all? { |v| v && v['kind'] == 'record' }

      selector = type['selector']
      guard_union_dispatch_keys_simple!(selector, ref)
      params = merged_params(variants.map { |v| v['fields'] })
      annotate_discriminator_enum!(params, selector)
      params
    end

    # A discriminated union's `by` field is validated against the whole allowed set:
    # the const values that tag each variant plus the default variant's own enum
    # values (e.g. continueWithAuth.action = {provideCredentials} + {default, cancel}).
    # That spans variants, so no single enum constant fits — emit an inline list.
    # Boolean discriminators (handleRequestDevicePrompt.accept) need no membership check.
    def annotate_discriminator_enum!(params, selector)
      by = selector['by']
      tagged = by ? selector['variants'].map { |v| v['value'] } : []
      return unless !tagged.empty? && tagged.all?(String)

      allowed = (tagged + default_variant_enum_values(selector, by)).uniq
      param = params.find { |p| p.wire_name == by }
      param.enum = "%w[#{allowed.join(' ')}]" if param
    end

    def default_variant_enum_values(selector, by)
      default = selector['default']
      field = default && @types[default]['fields'].find { |f| f['wire'] == by }
      ref = field && field['type']['ref']
      ref && @types[ref] && @types[ref]['kind'] == 'enum' ? @types[ref]['values'] : []
    end

    # Merge variant field lists into one flat param superset. A field is required only
    # when every variant declares it required; variant-specific fields become optional.
    def merged_params(variant_fields)
      all_fields = variant_fields.flatten
      all_fields.map { |f| f['wire'] }.uniq.map do |wire|
        field = all_fields.find { |f| f['wire'] == wire }
        required = variant_fields.all? { |fields| fields.any? { |f| f['wire'] == wire && f['required'] } }
        Param.new(ruby_name: BiDiGenerate.safe_field_name(BiDiGenerate.camel_to_snake(field['name'])),
                  wire_name: wire, required: required, rbs: rbs_type(field['type']))
      end
    end

    # `Union.build` matches the command's kwargs to the selector's dispatch keys by
    # symbol, which holds only while each dispatch wire key equals its ruby kwarg.
    # Every current key is a single lowercase word; fail generation if a new one is
    # camelCase so the outbound dispatch gets an explicit wire<->ruby mapping then.
    def guard_union_dispatch_keys_simple!(selector, ref)
      keys = selector['by'] ? [selector['by']] : (selector['ordered'] || []).flat_map { |arm| arm['requires'] }
      camel = keys.reject { |k| BiDiGenerate.camel_to_snake(k) == k }
      return if camel.empty?

      raise "union command param #{ref} dispatches on non-snake wire key(s) #{camel.inspect}; " \
            'Union.build matches kwargs to dispatch keys by symbol, so give the outbound ' \
            'dispatch an explicit wire<->ruby mapping before shipping this.'
    end
  end

  # Param kinds the named args can construct a Parameters object for (record fields,
  # or a union dispatched to one of its variants); anything else forwards a raw hash.
  PARAMS_CLASS_KINDS = %w[record union].freeze

  def self.build_ir(schema)
    schema.domains.map do |domain|
      Module.new(
        name: domain,
        ruby_class: snake_to_class_name(camel_to_snake(domain)),
        filename: camel_to_snake(domain),
        commands: schema.commands_for(domain).map { |cmd| build_command(schema, cmd) },
        events: schema.events_for(domain).map { |ev| build_event(ev) },
        enums: schema.enums_for(domain),
        types: nest_synthetic(schema.types_for(domain))
      )
    end
  end

  def self.build_command(schema, cmd)
    params = schema.params_for(cmd['params'])
    params_ref = cmd['params'] && cmd['params']['ref']
    params_kind = schema.type_kind(params_ref)
    params_class = type_class_name(params_ref) if params && !params.empty? && PARAMS_CLASS_KINDS.include?(params_kind)
    Command.new(
      wire_name: cmd['method'],
      method_name: safe_method_name(camel_to_snake(cmd['name'])),
      params: params || [],
      passthrough: params.nil?,
      result_ref: cmd['result'] && schema.structured_ref(cmd['result']['ref']),
      params_class: params_class,
      union_params: params_kind == 'union'
    )
  end

  def self.build_event(event)
    Event.new(wire_name: event['method'], event_name: camel_to_snake(event['name']))
  end

  # The projector tags lifted-out types with {synthetic, owner, label}. Emit each
  # synthetic record inside its owner's class body under its bare label, so
  # `Owner_Label` becomes the nested `Owner::Label` (refs resolve there via
  # ruby_path). Synthetic enums stay domain-level. Raises on a missing owner.
  def self.nest_synthetic(types)
    index = types.to_h { |t| [t.schema_name, t] }
    children = types.select { |t| !t.union? && t.synthetic }
    children.each do |child|
      owner = index[child.owner] ||
              raise("synthetic type #{child.schema_name} has no emitted owner #{child.owner}")
      owner.nested = (owner.nested || []) << child
      child.ruby_name = child.label
    end
    types - children
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
      when ['primitive'] then raise_unless(PRIMITIVES.include?(node['primitive']),
                                           "primitive #{node['primitive']} in #{owner}")
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

    emit(modules, output_dir, 'module.rb.erb', 'rb')
    emit(modules, sig_dir(output_dir), 'module.rbs.erb', 'rbs')
  end

  # Renders every module through one template and writes the result into target,
  # one file per module. Used for both the Ruby source and its RBS signatures.
  def self.emit(modules, output_dir, template, extension)
    target = File.join(workspace_root, output_dir)
    FileUtils.mkdir_p(target)

    tmpl = File.join(File.dirname(__FILE__), 'templates', template)
    modules.each do |mod|
      path = File.join(target, "#{mod.filename}.#{extension}")
      File.write(path, render(mod, tmpl))
      warn "bidi-generate: wrote #{path}"
    end
  end

  # The RBS signatures mirror the source tree under sig/ (the repo's convention),
  # e.g. rb/lib/.../protocol -> rb/sig/lib/.../protocol.
  def self.sig_dir(output_dir)
    output_dir.sub(%r{(\A|/)lib/}, '\1sig/lib/')
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
