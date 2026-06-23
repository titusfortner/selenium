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
        # Sentinel for an optional field the caller never set, kept distinct from an
        # explicit `nil`: an UNSET field is omitted from the wire entirely, whereas a
        # nullable field set to `nil` serializes as wire `null`.
        #
        # @api private
        UNSET = ::Object.new
        def UNSET.inspect = 'UNSET'
        UNSET.freeze

        # Recursively converts an arbitrary Ruby value to its wire shape. Needed
        # because a field value is not always a {Data} object: it may be an array,
        # an opaque hash (an Extensible slot or open map), or a scalar — none of
        # which respond to our +#as_json+. Each kind is dispatched explicitly rather
        # than assuming +#as_json+ exists.
        #
        # @param value [Object] a generated {Data}, an Array, a Hash, or a scalar
        # @return [Object] the wire representation (nested objects serialized,
        #   arrays/hashes mapped, scalars passed through)
        # @api private
        def self.as_wire(value)
          case value
          when Data::Wire then value.as_json
          when ::Array then value.map { |element| as_wire(element) }
          when ::Hash then value.transform_values { |element| as_wire(element) }
          else value
          end
        end

        # Factory and runtime base for the generated BiDi value types.
        #
        # +Data.define(spec)+ bakes each member's wire facts — wire name,
        # nullability, nested type ref, list-ness, and fixed discriminator value —
        # at *generation* time, and returns an immutable +::Data+ subclass with wire
        # (de)serialization mixed in. Data derived from those facts (resolved ref
        # classes, the Extensible key set) is memoized on the class at *load* time
        # (first use), so per-message work stays minimal at runtime: no +const_get+,
        # no recomputation.
        #
        # Outbound is always available (every object owns {Wire#as_json}); inbound
        # ({Builder#from_json}) reconstructs only what the schema names and passes
        # opaque slots through untouched.
        #
        # @example A generated record (discriminator + nested ref + nullable)
        #   class Cookie < Data.define(
        #     name:  'name',
        #     value: { wire: 'value', ref: 'Network::BytesValue' },
        #     extensible: true
        #   ); end
        #
        #   Cookie.from_json('name' => 'sid', 'value' => {'type' => 'string', 'value' => 'YQ=='})
        #
        # @api private
        class Data < ::Data
          # One generated member's baked wire facts.
          #
          # @!attribute [r] name    [Symbol] the ruby member name
          # @!attribute [r] wire    [String] the exact wire key
          # @!attribute [r] nullable [Boolean] whether an explicit nil serializes as wire null
          # @!attribute [r] ref     [String, nil] Protocol-relative class path for a nested type
          # @!attribute [r] list    [Boolean] whether the value is an array of +ref+
          # @!attribute [r] fixed   [Object] a forced discriminator value, or {UNSET}
          Member = ::Data.define(:name, :wire, :nullable, :ref, :list, :fixed)

          # Builds an immutable value class from a member spec.
          #
          # @param spec [Hash{Symbol => String, Hash}] maps each ruby member name to
          #   its wire name (string shorthand) or a +{wire:, nullable:, ref:, list:,
          #   fixed:}+ facts hash. The reserved +extensible: true+ option (not a
          #   member) adds opaque pass-through of unknown wire keys.
          # @return [Class] a +::Data+ subclass with {Wire} and {Builder} mixed in
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

          # @param name [Symbol, String] ruby member name
          # @param meta [String, Hash] wire name shorthand, or a facts hash
          # @return [Member]
          # @api private
          def self.member(name, meta)
            meta = {wire: meta} if meta.is_a?(::String)
            Member.new(name: name.to_sym, wire: meta.fetch(:wire, name.to_s),
                       nullable: meta[:nullable] || false, ref: meta[:ref],
                       list: meta[:list] || false, fixed: meta.fetch(:fixed, UNSET))
          end
          private_class_method :member

          # Class-level behavior prepended onto every generated class: a
          # ruby-keyword +.new+ and a wire +.from_json+. Prepended (not included) so
          # it overrides +::Data+'s generated +.new+.
          #
          # @api private
          module Builder
            # Constructs from ruby keywords, filling omitted optionals with {UNSET}
            # and forcing fixed (discriminator) members.
            #
            # @param kwargs [Hash{Symbol => Object}] member values by ruby name
            # @return [Data]
            def new(**kwargs)
              attributes = wire_members.to_h do |m|
                [m.name, fixed?(m) ? m.fixed : kwargs.fetch(m.name, UNSET)]
              end
              attributes[:extensions] = kwargs.fetch(:extensions, {}) if extensible?
              super(**attributes)
            end

            # Reconstructs from a wire hash. Members absent from the wire are left
            # {UNSET}; nested +ref+ members recurse; unknown keys land in
            # +extensions+ for extensible types. Returns the input unchanged when it
            # is not a Hash (an opaque value the schema does not name).
            #
            # @param wire [Hash, Object] the protocol response hash
            # @return [Data, Object]
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

            # @return [Boolean] whether the member carries a forced discriminator value
            def fixed?(member)
              !UNSET.equal?(member.fixed)
            end

            # Converts one inbound wire value, recursing into a nested type when the
            # member has a +ref+ (the resolved class is memoized per member).
            def read(member, raw)
              return raw if raw.nil? || member.ref.nil?

              klass = (@refs ||= {})[member.name] ||= Protocol.const_get(member.ref)
              member.list ? raw.map { |element| klass.from_json(element) } : klass.from_json(raw)
            end

            # @return [Hash] wire keys not declared as members (memoized key set)
            def extra(wire)
              known = (@wire_keys ||= wire_members.map(&:wire))
              wire.reject { |key, _| known.include?(key) }
            end
          end

          # Instance-level wire serialization mixed onto every generated class.
          #
          # @api private
          module Wire
            # Serializes to the wire hash: omits {UNSET} members, emits explicit
            # +null+ only for nullable members, recurses nested values via {as_wire},
            # and merges an extensible type's opaque extras.
            #
            # @return [Hash{String => Object}] the wire representation
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

        # Base for a discriminated union. Holds no data; it parses a wire hash into
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
            # @param wire [String] the shared discriminator wire key
            def discriminator(wire) = @discriminator = wire

            # @param table [Hash{Object => String}] discriminator value => class path
            def variants(table) = @variants = table

            # @param rules [Hash{String => Array<String>}] class path => required wire keys
            def presence(rules) = @presence = rules

            # @param path [String] class path for the no-discriminator variant
            def fallback(path) = @fallback = path

            # @param wire [Hash, Object] the protocol hash to dispatch on
            # @return [Data, Object] the parsed variant, or the input if not a Hash
            def from_json(wire)
              return wire unless wire.is_a?(::Hash)

              Protocol.const_get(select(wire)).from_json(wire)
            end

            private

            # @return [String] the matched variant's class path
            # @raise [ArgumentError] when no variant matches
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
