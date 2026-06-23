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

module Selenium
  module WebDriver
    class BiDi
      # Hand-written serialization runtime for the generated BiDi protocol layer.
      #
      # The generated classes under {BiDi::Protocol} are pure projections of the
      # schema; everything that knows *how* a value crosses the wire lives here, so
      # the +Protocol+ namespace stays exclusively machine-generated. Generated
      # value classes resolve {Data} and {Union} by lexical scope (every generated
      # file nests inside +class BiDi+), so the two base classes sit at this level —
      # alongside the existing {BiDi::Struct} — rather than inside +Protocol+.

      # Sentinel for an optional field the caller never set, kept distinct from an
      # explicit +nil+: an UNSET field is omitted from the JSON payload entirely,
      # whereas a nullable field set to +nil+ serializes as JSON +null+.
      #
      # @api private
      UNSET = ::Object.new
      def UNSET.inspect = 'UNSET'
      UNSET.freeze

      # Factory and runtime base for the generated BiDi value types.
      #
      # +Data.define(spec)+ bakes each field's JSON facts — JSON key, nullability,
      # nested type ref, list-ness, and fixed discriminator value — at *generation*
      # time, and returns an immutable +::Data+ subclass with JSON (de)serialization
      # mixed in. Data derived from those facts (resolved ref classes, the Extensible
      # key set) is memoized on the class at *load* time (first use), so per-message
      # work stays minimal at runtime: no +const_get+, no recomputation.
      #
      # Outbound is always available (every object owns {Serializable#as_json});
      # inbound ({Deserializer#from_json}) reconstructs only what the schema names
      # and passes opaque slots through untouched.
      #
      # @example A generated record (discriminator + nested ref + nullable)
      #   class Cookie < Data.define(
      #     name:  'name',
      #     value: { json_key: 'value', ref: 'Network::BytesValue' },
      #     extensible: true
      #   ); end
      #
      #   Cookie.from_json('name' => 'sid', 'value' => {'type' => 'string', 'value' => 'YQ=='})
      #
      # @api private
      class Data < ::Data
        # One generated field's baked JSON facts. Named +Field+ (not +Member+) to
        # avoid cognitive overlap with +::Data#members+.
        #
        # @!attribute [r] name     [Symbol] the ruby reader name
        # @!attribute [r] json_key [String] the exact JSON payload key
        # @!attribute [r] nullable [Boolean] whether an explicit nil serializes as JSON null
        # @!attribute [r] ref      [String, nil] Protocol-relative class path for a nested type
        # @!attribute [r] list     [Boolean] whether the value is an array of +ref+
        # @!attribute [r] fixed    [Object] a forced discriminator value, or {UNSET}
        Field = ::Data.define(:name, :json_key, :nullable, :ref, :list, :fixed)

        # Builds an immutable value class from a field spec.
        #
        # @param spec [Hash{Symbol => String, Hash}] maps each ruby field name to
        #   its JSON key (string shorthand) or a +{json_key:, nullable:, ref:, list:,
        #   fixed:}+ facts hash. The reserved +extensible: true+ option (not a field)
        #   adds opaque pass-through of unknown JSON keys.
        # @return [Class] a +::Data+ subclass with {Serializable} and {Deserializer}
        #   mixed in
        def self.define(**spec)
          extensible = spec.delete(:extensible) || false
          fields = spec.map { |name, meta| field(name, meta) }
          names = fields.map(&:name)
          names << :extensions if extensible

          klass = super(*names)
          fields.freeze
          # Singleton methods (unlike instance variables) are inherited by the
          # generated subclass, so the baked facts reach `class X < Data.define(…)`.
          klass.define_singleton_method(:fields) { fields }
          klass.define_singleton_method(:extensible?) { extensible }
          klass.include(Serializable)
          klass.singleton_class.prepend(Deserializer)
          klass
        end

        # @param name [Symbol, String] ruby field name
        # @param meta [String, Hash] JSON key shorthand, or a facts hash
        # @return [Field]
        # @api private
        def self.field(name, meta)
          meta = {json_key: meta} if meta.is_a?(::String)
          Field.new(name: name.to_sym, json_key: meta.fetch(:json_key, name.to_s),
                    nullable: meta[:nullable] || false, ref: meta[:ref],
                    list: meta[:list] || false, fixed: meta.fetch(:fixed, UNSET))
        end
        private_class_method :field

        # Class-level behavior prepended onto every generated class: a ruby-keyword
        # +.new+ and a JSON +.from_json+. Prepended (not included) so it overrides
        # +::Data+'s generated +.new+. Named {Deserializer} for its inbound role of
        # parsing a JSON payload into the value object.
        #
        # @api private
        module Deserializer
          # Constructs from ruby keywords, filling omitted optionals with {UNSET}
          # and forcing fixed (discriminator) fields.
          #
          # @param kwargs [Hash{Symbol => Object}] field values by ruby name
          # @return [Data]
          def new(**kwargs)
            attributes = fields.to_h do |f|
              [f.name, fixed?(f) ? f.fixed : kwargs.fetch(f.name, UNSET)]
            end
            attributes[:extensions] = kwargs.fetch(:extensions, {}) if extensible?
            super(**attributes)
          end

          # Reconstructs from a JSON payload hash. Fields absent from the payload are
          # left {UNSET}; nested +ref+ fields recurse; unknown keys land in
          # +extensions+ for extensible types. Returns the input unchanged when it is
          # not a Hash (an opaque value the schema does not name).
          #
          # @param json_payload [Hash, Object] the protocol response hash
          # @return [Data, Object]
          def from_json(json_payload)
            return json_payload unless json_payload.is_a?(::Hash)

            attributes = {}
            fields.each do |f|
              next if fixed?(f)

              attributes[f.name] = read(f, json_payload[f.json_key]) if json_payload.key?(f.json_key)
            end
            attributes[:extensions] = extra(json_payload) if extensible?
            new(**attributes)
          end

          private

          # @return [Boolean] whether the field carries a forced discriminator value
          def fixed?(field)
            !UNSET.equal?(field.fixed)
          end

          # Converts one inbound JSON value, recursing into a nested type when the
          # field has a +ref+ (the resolved class is memoized per field).
          def read(field, raw)
            return raw if raw.nil? || field.ref.nil?

            klass = (@refs ||= {})[field.name] ||= Protocol.const_get(field.ref)
            field.list ? raw.map { |element| klass.from_json(element) } : klass.from_json(raw)
          end

          # @return [Hash] JSON keys not declared as fields (memoized key set)
          def extra(json_payload)
            known = (@json_keys ||= fields.map(&:json_key))
            json_payload.reject { |key, _| known.include?(key) }
          end
        end

        # Instance-level JSON serialization mixed onto every generated class. The
        # mixin both provides the per-object +#as_json+ and, via {Serializable.as_json},
        # the recursive value dispatcher its fields need.
        #
        # @api private
        module Serializable
          # Recursively converts an arbitrary Ruby value to its JSON shape. Same
          # purpose as {#as_json}, but for a value that is not necessarily a {Data}
          # object: it may be an array, an opaque hash (an Extensible slot or open
          # map), or a scalar — none of which carry +#as_json+. Each kind is
          # dispatched explicitly rather than assuming +#as_json+ exists.
          #
          # @param value [Object] a generated {Data}, an Array, a Hash, or a scalar
          # @return [Object] the JSON representation (nested objects serialized,
          #   arrays/hashes mapped, scalars passed through)
          def self.as_json(value)
            case value
            when Serializable then value.as_json
            when ::Array then value.map { |element| as_json(element) }
            when ::Hash then value.transform_values { |element| as_json(element) }
            else value
            end
          end

          # Serializes this object to its JSON payload: omits {UNSET} fields, emits
          # explicit +null+ only for nullable fields, recurses nested values via
          # {Serializable.as_json}, and merges an extensible type's opaque extras.
          #
          # @return [Hash{String => Object}] the JSON representation
          def as_json(*)
            payload = {}
            self.class.fields.each do |f|
              value = public_send(f.name)
              next if UNSET.equal?(value)
              next if value.nil? && !f.nullable

              payload[f.json_key] = Serializable.as_json(value)
            end
            payload.merge!(extensions) if self.class.extensible? && !extensions.empty?
            payload
          end
        end
      end

      # Base for a discriminated union. Holds no data; it parses a JSON payload into
      # the right variant class. A shared discriminator gives O(1) table dispatch;
      # presence rules and a no-tag fallback cover unions without a shared tag.
      #
      # @example
      #   class Locator < Union
      #     discriminator 'type'
      #     variants('css' => 'BrowsingContext::CssLocator')
      #   end
      #
      # @api private
      class Union
        class << self
          # @param json_key [String] the shared discriminator JSON key
          def discriminator(json_key) = @discriminator = json_key

          # @param table [Hash{Object => String}] discriminator value => class path
          def variants(table) = @variants = table

          # @param rules [Hash{String => Array<String>}] class path => required JSON keys
          def presence(rules) = @presence = rules

          # @param path [String] class path for the no-discriminator variant
          def fallback(path) = @fallback = path

          # @param json_payload [Hash, Object] the protocol hash to dispatch on
          # @return [Data, Object] the parsed variant, or the input if not a Hash
          def from_json(json_payload)
            return json_payload unless json_payload.is_a?(::Hash)

            Protocol.const_get(select(json_payload)).from_json(json_payload)
          end

          private

          # @return [String] the matched variant's class path
          # @raise [ArgumentError] when no variant matches
          def select(json_payload)
            tag = @discriminator && json_payload[@discriminator]
            return @variants[tag] if tag && @variants&.key?(tag)

            @presence&.each { |path, keys| return path if keys.all? { |k| json_payload.key?(k) } }
            @fallback || raise(::ArgumentError, "no #{name} variant matches #{json_payload.inspect}")
          end
        end
      end
    end # BiDi
  end # WebDriver
end # Selenium
