# encoding: utf-8
#
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

    #
    # @api private
    # @see ActionBuilder

    class Keyboard

      def initialize(bridge)
        @bridge = bridge
      end

      def send_keys(*keys)
        @bridge.sendKeysToActiveElement Keys.encode(keys)
      end

      #
      # Press a modifier key
      #
      # @see Selenium::WebDriver::Keys
      #

      def press(key)
        assert_modifier key

        @bridge.sendKeysToActiveElement Keys.encode([key])
      end

      #
      # Release a modifier key
      #
      # @see Selenium::WebDriver::Keys
      #

      def release(key)
        assert_modifier key

        @bridge.sendKeysToActiveElement Keys.encode([key])
      end

      private

      MODIFIERS = [:control, :shift, :alt, :command, :meta]

      def assert_modifier(key)
        return if MODIFIERS.include? key
        raise ArgumentError, "#{key.inspect} is not a modifier key, expected one of #{MODIFIERS.inspect}"
      end

    end # Keyboard
  end # WebDriver
end  # Selenium
