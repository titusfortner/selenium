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
    class BrowserOptions

      VALID_W3C = %i[browser_name browser_version platform_name accept_insecure_certs page_load_strategy proxy
      set_window_rect timeouts unhandled_prompt_behavior strict_file_interactability]

      #
      # Create a new Options instance with w3c compatible values.
      #

      def initialize(**opts)
        VALID_W3C.each do |capability|
          next unless opts.key?(capability)

          instance_variable_set("@#{capability}", opts.delete(capability))
        end

        validate_proxy if @proxy

        raise "Unknown capabilities requested #{opts.inspect}" unless opts.empty?
      end

      def to_json(*)
        JSON.generate as_json
      end

      def ==(other)
        return false unless other.is_a? self.class
        as_json == other.as_json
      end

      protected

      def as_json(*)
        VALID_W3C.each_with_object({}) do |key, hash|
          value = VALID_W3C[key].respond_to?(:as_json) ? VALID_W3C[key].as_json : VALID_W3C[key]
          key = camel_case(key.to_s) if key.is_a?(Symbol)

          error = "expected String or Symbol, got #{key.inspect}:#{key.class} / #{value.inspect}"
          raise TypeError, error unless key.is_a?(String)

          hash[key] = value
        end
      end

      private

      def validate_proxy
        return if @proxy.is_a? Proxy

        raise TypeError, "expected Hash or Proxy, got #{proxy.inspect}:#{proxy.class}" unless @proxy.respond_to?(:to_h)

        @proxy = Proxy.new(@proxy)
      end
    end # Options
  end # WebDriver
end # Selenium
