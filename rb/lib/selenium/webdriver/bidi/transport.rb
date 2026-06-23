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
      # Low-level command seam for the generated Protocol layer: renders command
      # params (including generated value objects) to the wire, sends, and parses the
      # reply into the command's declared type. Stateless — session state lives above.
      #
      # @api private
      class Transport
        def initialize(connection)
          @connection = connection
        end

        def execute(method, params = {}, returns: nil)
          message = @connection.send_cmd(method: method, params: render(params))
          raise Error::WebDriverError, error_message(message) if message['error']

          result = message['result']
          returns ? returns.from_json(result) : result
        end

        private

        # nil/UNSET omit the param; NULL sends an explicit wire null; anything else
        # (scalars, generated objects, arrays) renders through Serializable.
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
