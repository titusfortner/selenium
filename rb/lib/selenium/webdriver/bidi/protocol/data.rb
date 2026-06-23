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

        # Recursively converts a value to its wire shape. Generated value objects
        # serialize through their own #as_json; arrays map; hashes (opaque /
        # Extensible slots) pass through with their already-wire keys.
        def self.as_wire(value)
          case value
          when Data::Wire then value.as_json
          when ::Array then value.map { |element| as_wire(element) }
          when ::Hash then value.transform_values { |element| as_wire(element) }
          else value
          end
        end

        # Factory for the generated BiDi value types. `Data.define(spec)` bakes each
        # member's wire facts (wire name, nullability, nested ref, list-ness, fixed
        # discriminator value) at generation time and produces an immutable `::Data`
        # subclass with wire (de)serialization mixed in. Derived data (resolved ref
        # classes, the Extensible key set) is memoized on the class at first use, so
        # per-message work stays minimal — no `const_get`, no recomputation, at call
        # time. Outbound (`#as_json`) is always available; inbound (`.from_json`)
        # reconstructs only what the schema names and passes opaque slots through.
        class Data < ::Data
          Member = ::Data.define(:name, :wire, :nullable, :ref, :list, :fixed)

          # spec maps `ruby_name => 'wireName'` (shorthand) or
          # `ruby_name => { wire:, nullable:, ref:, list:, fixed: }`. `extensible:`
          # is a reserved option, not a member.
          def self.define(**spec)
            extensible = spec.delete(:extensible) || false
            members = spec.map { |name, meta| member(name, meta) }
            names = members.map(&:name)
            names << :extensions if extensible

            klass = super(*names)
            members.freeze
            # Singleton methods (unlike instance variables) are inherited by the
            # generated subclass, so the baked facts reach `class X < Data.define(…)`.
            klass.define_singleton_method(:wire_members) { members }
            klass.define_singleton_method(:extensible?) { extensible }
            klass.include(Wire)
            klass.singleton_class.prepend(Builder)
            klass
          end

          def self.member(name, meta)
            meta = {wire: meta} if meta.is_a?(::String)
            Member.new(name: name.to_sym, wire: meta.fetch(:wire, name.to_s),
                       nullable: meta[:nullable] || false, ref: meta[:ref],
                       list: meta[:list] || false, fixed: meta.fetch(:fixed, UNSET))
          end
          private_class_method :member

          # Class-level behavior mixed onto each generated class: ruby-keyword `new`
          # (fills omitted optionals with UNSET, forces fixed members) and wire
          # `from_json`. Prepended so it overrides ::Data's generated `new`.
          module Builder
            def new(**kwargs)
              attributes = wire_members.to_h do |m|
                [m.name, fixed?(m) ? m.fixed : kwargs.fetch(m.name, UNSET)]
              end
              attributes[:extensions] = kwargs.fetch(:extensions, {}) if extensible?
              super(**attributes)
            end

            def from_json(wire)
              return wire unless wire.is_a?(::Hash)

              attributes = {}
              wire_members.each do |m|
                next if fixed?(m)

                attributes[m.name] = read(m, wire[m.wire]) if wire.key?(m.wire)
              end
              attributes[:extensions] = extra(wire) if extensible?
              new(**attributes)
            end

            private

            def fixed?(member)
              !UNSET.equal?(member.fixed)
            end

            def read(member, raw)
              return raw if raw.nil? || member.ref.nil?

              klass = (@refs ||= {})[member.name] ||= Protocol.const_get(member.ref)
              member.list ? raw.map { |element| klass.from_json(element) } : klass.from_json(raw)
            end

            def extra(wire)
              known = (@wire_keys ||= wire_members.map(&:wire))
              wire.reject { |key, _| known.include?(key) }
            end
          end

          # Instance-level wire serialization mixed onto each generated class.
          module Wire
            def as_json(*)
              json = {}
              self.class.wire_members.each do |m|
                value = public_send(m.name)
                next if UNSET.equal?(value)
                next if value.nil? && !m.nullable

                json[m.wire] = Protocol.as_wire(value)
              end
              json.merge!(extensions) if self.class.extensible? && !extensions.empty?
              json
            end
          end
        end

        # Discriminated union — holds no data, parses a wire hash into the right
        # variant. The discriminator table gives O(1) dispatch; presence rules and a
        # no-tag fallback cover unions without a shared tag.
        class Union
          class << self
            def discriminator(wire) = @discriminator = wire
            def variants(table) = @variants = table
            def presence(rules) = @presence = rules
            def fallback(path) = @fallback = path

            def from_json(wire)
              return wire unless wire.is_a?(::Hash)

              Protocol.const_get(select(wire)).from_json(wire)
            end

            private

            def select(wire)
              tag = @discriminator && wire[@discriminator]
              return @variants[tag] if tag && @variants&.key?(tag)

              @presence&.each { |path, keys| return path if keys.all? { |k| wire.key?(k) } }
              @fallback || raise(::ArgumentError, "no #{name} variant matches #{wire.inspect}")
            end
          end
        end
      end # Protocol
    end # BiDi
  end # WebDriver
end # Selenium
