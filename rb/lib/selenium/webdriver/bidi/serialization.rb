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
      # Serialization runtime for the generated BiDi protocol layer. Data and Union
      # sit at this level (not under Protocol) so generated classes resolve them by
      # lexical scope while Protocol stays exclusively machine-generated.

      # Omitted optional: dropped from the payload entirely (vs. nil, which a nullable
      # field serializes as wire null).
      #
      # @api private
      UNSET = ::Object.new
      def UNSET.inspect = 'UNSET'
      UNSET.freeze

      # Factory and runtime base for the generated value types. +Data.define(spec)+
      # bakes each field's wire facts at generation time and returns an immutable
      # +::Data+ subclass with serialization mixed in.
      #
      #   class Cookie < Data.define(name: 'name', value: {json_key: 'value', ref: 'Network::BytesValue'}); end
      #
      # @api private
      class Data < ::Data
        # Named Field, not Member, to avoid overlap with +::Data#members+.
        Field = ::Data.define(:name, :json_key, :nullable, :ref, :list, :fixed)

        # spec maps each ruby field name to its JSON key (string) or a facts hash
        # ({json_key:, nullable:, ref:, list:, fixed:}); +extensible: true+ adds
        # pass-through of unknown keys.
        def self.define(**spec)
          extensible = spec.delete(:extensible) || false
          fields = spec.map { |name, meta| field(name, meta) }
          names = fields.map(&:name)
          names << :extensions if extensible

          klass = super(*names)
          fields.freeze
          # Singleton methods are inherited by `class X < Data.define(…)`; instance
          # variables would not be.
          klass.define_singleton_method(:fields) { fields }
          klass.define_singleton_method(:extensible?) { extensible }
          klass.include(Serializable)
          klass.singleton_class.prepend(Deserializer)
          klass
        end

        def self.field(name, meta)
          meta = {json_key: meta} if meta.is_a?(::String)
          Field.new(name: name.to_sym, json_key: meta.fetch(:json_key, name.to_s),
                    nullable: meta[:nullable] || false, ref: meta[:ref],
                    list: meta[:list] || false, fixed: meta.fetch(:fixed, UNSET))
        end
        private_class_method :field

        # Ruby-keyword +.new+ and wire +.from_json+. Prepended (not included) so it
        # overrides +::Data+'s generated +.new+.
        #
        # @api private
        module Deserializer
          def new(**kwargs)
            attributes = fields.to_h do |f|
              [f.name, fixed?(f) ? f.fixed : kwargs.fetch(f.name, UNSET)]
            end
            attributes[:extensions] = kwargs.fetch(:extensions, {}) if extensible?
            super(**attributes)
          end

          # Absent fields stay UNSET; ref fields recurse; unknown keys land in
          # +extensions+. A non-Hash payload is an opaque value the schema does not
          # name, returned unchanged.
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

          def fixed?(field)
            !UNSET.equal?(field.fixed)
          end

          def read(field, raw)
            return raw if raw.nil? || field.ref.nil?

            klass = (@refs ||= {})[field.name] ||= Protocol.const_get(field.ref)
            field.list ? raw.map { |element| klass.from_json(element) } : klass.from_json(raw)
          end

          def extra(json_payload)
            known = (@json_keys ||= fields.map(&:json_key))
            json_payload.reject { |key, _| known.include?(key) }
          end
        end

        # @api private
        module Serializable
          # Recurses an arbitrary value (object, array, hash, or scalar) to its wire
          # shape — the non-object kinds don't carry +#as_json+.
          def self.as_json(value)
            case value
            when Serializable then value.as_json
            when ::Array then value.map { |element| as_json(element) }
            when ::Hash then value.transform_values { |element| as_json(element) }
            else value
            end
          end

          # Omits UNSET fields, emits null only for nullable fields, recurses values,
          # and merges an extensible type's extras.
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

      # Parses a wire hash into the right variant: a shared discriminator gives table
      # dispatch; presence rules and a no-tag fallback cover unions without one.
      #
      #   class Locator < Union
      #     discriminator 'type'
      #     variants('css' => 'BrowsingContext::CssLocator')
      #   end
      #
      # @api private
      class Union
        class << self
          def discriminator(json_key) = @discriminator = json_key
          def variants(table) = @variants = table
          def presence(rules) = @presence = rules
          def fallback(path) = @fallback = path

          def from_json(json_payload)
            return json_payload unless json_payload.is_a?(::Hash)

            Protocol.const_get(select(json_payload)).from_json(json_payload)
          end

          private

          def select(json_payload)
            # Look up the discriminator value (which may legitimately be null, e.g.
            # script.NullValue's `type`) when the key is present, before falling back
            # to presence rules and the no-tag default.
            if @discriminator && json_payload.key?(@discriminator)
              tag = json_payload[@discriminator]
              return @variants[tag] if @variants&.key?(tag)
            end

            @presence&.each { |path, keys| return path if keys.all? { |k| json_payload.key?(k) } }
            @fallback || raise(::ArgumentError, "no #{name} variant matches #{json_payload.inspect}")
          end
        end
      end
    end # BiDi
  end # WebDriver
end # Selenium
