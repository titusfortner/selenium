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
      # Low-level command transport for the generated {BiDi::Protocol} layer. Owns
      # the websocket and turns a Ruby command (method + params) into a wire message,
      # then parses the reply. It centralizes serialization of the generated value
      # objects — so the generated command methods stay thin: they hand Transport
      # Ruby values (scalars, generated {Data} objects, arrays, or {NULL}) and
      # Transport renders them to the wire shape. Inbound, it parses the result into
      # the command's declared value type.
      #
      # @api private
      class Transport
        # @param connection [#send_cmd] the websocket connection (a
        #   {WebSocketConnection}, or any object that takes +method:+/+params:+ and
        #   returns the reply hash).
        def initialize(connection)
          @connection = connection
        end

        # Sends one command and returns its result.
        #
        # @param method [String] the BiDi method name (e.g. "browsingContext.navigate")
        # @param params [Hash{Symbol => Object}] params keyed by their wire name; a
        #   value may be a scalar, a generated {Data} value object, an array, +nil+
        #   (omitted), or {NULL} (explicit wire +null+).
        # @param returns [Class, nil] a {Protocol} value type whose +.from_json+
        #   parses the result, or nil to return the raw result hash.
        # @return [Object] the parsed result, or the raw result hash
        # @raise [Error::WebDriverError] when the command reports an error
        def execute(method, params = {}, returns: nil)
          message = @connection.send_cmd(method: method, params: render(params))
          raise Error::WebDriverError, error_message(message) if message['error']

          result = message['result']
          returns ? returns.from_json(result) : result
        end

        private

        # Renders command params to their wire shape: drops omitted params (+nil+ or
        # {UNSET}), serializes {NULL} to an explicit wire +null+, and recurses through
        # generated value objects / arrays / hashes via {Data::Serializable.as_json}.
        def render(params)
          params.each_with_object({}) do |(key, value), wire|
            next if value.nil? || UNSET.equal?(value)

            wire[key] = NULL.equal?(value) ? nil : Data::Serializable.as_json(value)
          end
        end

        def error_message(message)
          "#{message['error']}: #{message['message']}\n#{message['stacktrace']}"
        end
      end # Transport
    end # BiDi
  end # WebDriver
end # Selenium
