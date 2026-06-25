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
      # Low-level command seam for the generated Protocol layer: serializes a command's
      # params object to the wire, sends over the raw websocket, and parses the reply
      # into the command's declared type. Stateless — session state lives above.
      #
      # @api private
      class Transport
        # Resolves the Transport reachable from a Driver, a bridge, or a Transport, so
        # a generated domain can be constructed with any of them. The bridge owns the
        # Transport (built over its websocket in BiDiBridge#create_session).
        def self.for(context)
          return context if context.is_a?(self)
          return context.transport if context.respond_to?(:transport)
          return context.send(:bridge).transport if context.respond_to?(:bridge, true)

          raise Error::WebDriverError,
                "Cannot resolve a BiDi::Transport from #{context.inspect}; expected a Transport, a bridge, or a driver"
        end

        def initialize(connection)
          @connection = connection
        end

        # cmd is the wire method; params the command's value object (or nil); result the
        # value type the reply parses into (or nil to return the raw result hash).
        def execute(cmd:, params: nil, result: nil)
          reply = @connection.send_cmd(method: cmd, params: serialize(params))
          # BiDi reuses the W3C error codes, so map them to the same typed
          # exceptions as the HTTP path (e.g. 'unknown command' lets callers fall
          # back to classic behavior); unrecognized codes degrade to WebDriverError.
          raise Error.for_error(reply['error']), error_message(reply) if reply['error']

          value = reply['result']
          result ? result.from_json(value) : value
        end

        private

        # A params object renders itself; a passthrough Hash drops omitted entries and
        # serializes any nested value objects; no params is an empty payload.
        def serialize(params)
          case params
          when nil then {}
          when ::Hash
            params.reject { |_, value| value.nil? || UNSET.equal?(value) }
                  .transform_values { |value| Data::Serializable.as_json(value) }
          else params.as_json
          end
        end

        def error_message(reply)
          "#{reply['error']}: #{reply['message']}\n#{reply['stacktrace']}"
        end
      end # Transport
    end # BiDi
  end # WebDriver
end # Selenium
