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
    module Chrome

      #
      # Driver implementation for Chrome.
      # @api private
      #

      class Driver < WebDriver::Driver
        include DriverExtensions::HasNetworkConditions
        include DriverExtensions::HasTouchScreen
        include DriverExtensions::HasWebStorage
        include DriverExtensions::HasLocation
        include DriverExtensions::TakesScreenshot
        include DriverExtensions::DownloadsFiles

        def initialize(opts = {})
          opts = opts.dup
          opts[:desired_capabilities] = create_capabilities(opts)

          opts[:url] ||= service_url(opts)

          listener = opts.delete(:listener)
          @bridge = Remote::Bridge.handshake(opts)
          @bridge.extend Bridge

          super(@bridge, listener: listener)
        end

        def browser
          :chrome
        end

        def quit
          super
        ensure
          @service&.stop
        end

        def execute_cdp(cmd, **params)
          @bridge.send_command(cmd: cmd, params: params)
        end

        private

        def create_capabilities(opts)
          options = opts.delete(:options) { Options.new }

          caps = opts.delete(:desired_capabilities)
          if caps
            WebDriver.logger.deprecate ':desired_capabilities to initialize a driver',
                                        'options: <Selenium::WebDriver::Chrome::Options>'
          end

          args = opts.delete(:args) || opts.delete(:switches)
          if args
            WebDriver.logger.deprecate ':args or :switches',
                                       'Selenium::WebDriver::Chrome::Options#initialize or #args='
            raise ArgumentError, ':args must be an Array of Strings' unless args.is_a? Array

            args.each { |arg| options.add_argument(arg.to_s) }
          end

          profile = opts.delete(:profile)
          if profile
            profile = profile.as_json

            options.add_argument("--user-data-dir=#{profile['directory']}") if options.args.none? { |arg| arg =~ /user-data-dir/ }

            if profile['extensions']
              WebDriver.logger.deprecate 'Using Selenium::WebDriver::Chrome::Profile#extensions',
                                         'Selenium::WebDriver::Chrome::Options#initialize or #extensions='
              profile['extensions'].each do |extension|
                options.add_encoded_extension(extension)
              end
            end
          end

          detach = opts.delete(:detach)
          if detach
            WebDriver.logger.deprecate ':detach to initialize a driver',
                                       'Selenium::WebDriver::Chrome::Options#initialize or #detach'
            options.add_option(:detach, true)
          end

          prefs = opts.delete(:prefs)
          if prefs
            WebDriver.logger.deprecate ':prefs to initialize a driver',
                                       'Selenium::WebDriver::Chrome::Options#initialize or #prefs='
            prefs.each do |key, value|
              options.add_preference(key, value)
            end
          end

          options = caps.merge!(options) if caps

          options[:proxy] = opts.delete(:proxy) if opts.key?(:proxy)
          options[:proxy] ||= opts.delete('proxy') if opts.key?('proxy')

          options.as_json
        end
      end # Driver
    end # Chrome
  end # WebDriver
end # Selenium
