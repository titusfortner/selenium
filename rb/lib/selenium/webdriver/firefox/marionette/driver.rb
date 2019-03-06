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
    module Firefox
      module Marionette

        #
        # Driver implementation for Firefox using GeckoDriver.
        # @api private
        #

        class Driver < WebDriver::Driver
          include DriverExtensions::HasAddons
          include DriverExtensions::HasWebStorage
          include DriverExtensions::TakesScreenshot

          def initialize(opts = {})
            options = opts.delete(:options) { Options.new }
            options = Array[options].map(&:as_json).reduce({}, :merge)

            unless opts.key?(:url)
              driver_path = opts.delete(:driver_path) || Firefox.driver_path
              driver_opts = opts.delete(:driver_opts) || {}
              port = opts.delete(:port) || Service::DEFAULT_PORT

              @service = Service.new(driver_path, port, driver_opts)
              @service.start
              opts[:url] = @service.uri
            end

            listener = opts.delete(:listener)
            WebDriver.logger.info 'Skipping handshake as we know it is W3C.'

            bridge = Remote::Bridge.new(opts)
            capabilities = bridge.create_session(options.as_json)
            @bridge = Remote::W3C::Bridge.new(capabilities, bridge.session_id, opts)
            @bridge.extend Marionette::Bridge

            super(@bridge, listener: listener)
          end

          def browser
            :firefox
          end

          def quit
            super
          ensure
            @service.stop if @service
          end
        end # Driver
      end # Marionette
    end # Firefox
  end # WebDriver
end # Selenium
