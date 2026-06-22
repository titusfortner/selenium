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
      module Protocol
        # Sentinel for an optional field the caller never set. Distinct from an
        # explicit nil, which a nullable field serializes as wire `null`; an UNSET
        # field is omitted from the wire entirely.
        UNSET = ::Object.new
        def UNSET.inspect = 'UNSET'
        UNSET.freeze

        # Mixed into the generated BiDi value types, which are immutable `::Data`
        # classes. It adds wire (de)serialization driven by per-field metadata the
        # generator declares (#field, #discriminator, #extensible!). Nested
        # structured fields reference their class by path string, resolved lazily
        # so recursion and cross-domain references carry no load-order constraints.
        module Serializable
          Field = ::Data.define(:name, :wire, :required, :nullable, :ref, :list)

          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            def wire_fields
              @wire_fields ||= []
            end

            def discriminator_info
              @discriminator_info
            end

            def extensible?
              @extensible || false
            end

            def field(name, wire:, required: false, nullable: false, ref: nil, list: false)
              wire_fields << Field.new(name: name, wire: wire, required: required, nullable: nullable, ref: ref, list: list)
            end

            # A baked variant discriminator (e.g. `type: "css"`): always emitted on
            # the wire, never a constructor argument.
            def discriminator(wire:, value:)
              @discriminator_info = {wire: wire, value: value}
            end

            def extensible!
              @extensible = true
            end

            # Fills omitted optional fields with UNSET so the underlying Data does
            # not demand them, while still enforcing required ones.
            def new(**kwargs)
              wire_fields.each do |f|
                raise ::ArgumentError, "missing keyword: :#{f.name}" if f.required && !kwargs.key?(f.name)
              end
              kwargs[:extensions] = {} if extensible? && !kwargs.key?(:extensions)
              members.each { |m| kwargs[m] = UNSET unless kwargs.key?(m) }
              super(**kwargs)
            end

            def from_wire(hash)
              return hash unless hash.is_a?(::Hash)

              kwargs = {}
              wire_fields.each do |f|
                kwargs[f.name] = parse_value(f, hash[f.wire]) if hash.key?(f.wire)
              end
              kwargs[:extensions] = extra_keys(hash) if extensible?
              new(**kwargs)
            end

            def parse_value(field, raw)
              return raw if raw.nil? || field.ref.nil?

              klass = Protocol.const_get(field.ref)
              field.list ? Array(raw).map { |element| klass.from_wire(element) } : klass.from_wire(raw)
            end

            def extra_keys(hash)
              known = wire_fields.map(&:wire)
              known << discriminator_info[:wire] if discriminator_info
              hash.reject { |k, _| known.include?(k) }
            end
          end

          def to_wire
            wire = {}
            disc = self.class.discriminator_info
            wire[disc[:wire]] = disc[:value] if disc
            self.class.wire_fields.each do |f|
              value = public_send(f.name)
              next if UNSET.equal?(value)
              next if value.nil? && !f.nullable

              wire[f.wire] = serialize_value(f, value)
            end
            wire.merge!(extensions) if self.class.extensible? && extensions.is_a?(::Hash)
            wire
          end

          private

          def serialize_value(field, value)
            return value if value.nil? || field.ref.nil?

            field.list ? value.map { |element| wire_of(element) } : wire_of(value)
          end

          def wire_of(value)
            value.respond_to?(:to_wire) ? value.to_wire : value
          end
        end

        # Base for discriminated unions. A union holds no data; it parses a wire
        # hash into the right variant. Variants are referenced by class-path string
        # (resolved lazily). Three dispatch shapes are supported: a shared
        # discriminator value, a no-discriminator fallback variant, and
        # presence-based selection by which required fields are present.
        class Union
          Variant = ::Data.define(:value, :ref, :requires)

          class << self
            def variants
              @variants ||= []
            end

            def discriminator_wire(wire = nil)
              @discriminator_wire = wire if wire
              @discriminator_wire
            end

            def variant(value, ref)
              variants << Variant.new(value: value, ref: ref, requires: nil)
            end

            def fallback(ref)
              variants << Variant.new(value: :fallback, ref: ref, requires: nil)
            end

            def presence_variant(ref, requires:)
              variants << Variant.new(value: :presence, ref: ref, requires: requires)
            end

            def from_wire(hash)
              return hash unless hash.is_a?(::Hash)

              Protocol.const_get(select_variant(hash).ref).from_wire(hash)
            end

            def select_variant(hash)
              if discriminator_wire && hash.key?(discriminator_wire)
                matched = variants.find { |v| v.value == hash[discriminator_wire] }
                return matched if matched
              end
              presence = variants.find { |v| v.requires&.all? { |w| hash.key?(w) } }
              presence || variants.find { |v| v.value == :fallback } ||
                raise(::ArgumentError, "no #{name} variant matches #{hash.inspect}")
            end
          end
        end
      end # Protocol
    end # BiDi
  end # WebDriver
end # Selenium
