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
      class Options < WebDriver::BrowserOptions

        attr_reader :binary, :log_level, :args, :prefs, :profile, :options

        KEY = 'moz:firefoxOptions'.freeze

        #
        # Create a new Options instance, only for W3C-capable versions of Firefox.
        #
        # see: https://firefox-source-docs.mozilla.org/testing/geckodriver/Capabilities.html
        #
        # @example
        #   options = Selenium::WebDriver::Firefox::Options.new(args: ['--host=127.0.0.1'])
        #   driver = Selenium::WebDriver.for :firefox, options: options
        #
        # @param [Hash] opts the pre-defined options to create the Firefox::Options with
        # @option opts [String] :binary Path to the Firefox executable to use
        # @option opts [Array<String>] :args List of command-line arguments to use when starting geckodriver
        # @option opts [Profile, String] :profile Encoded profile string or Profile instance
        # @option opts [String, Symbol] :log_level Log level for geckodriver
        # @option opts [Hash] :prefs A hash with each entry consisting of the key of the preference and its value
        #

        def initialize(args: [], binary: nil, profile: nil, log_level: nil, prefs: {}, **opts)
          opts[:browser_name] = 'firefox'

          @args = args
          @binary = binary
          @profile = profile
          validate_profile if @profile

          @log_level = log_level
          @prefs = prefs
          @options = {}

          super(opts)
        end

        #
        # Allow extensibility in case additional capabilities are added by Mozilla
        #
        # @example
        #   options = Selenium::WebDriver::Firefox::Options.new(args: ['--host=127.0.0.1'])
        #   driver = Selenium::WebDriver.for :firefox, options: options
        #

        def add_option(key, value)
          @options[key] = value
        end

        protected

        #
        # @api private
        #

        def as_json(*)
          opts = @options

          opts[:profile] = @profile.encoded if @profile
          opts[:args] = @args.to_a if @args.any?
          opts[:binary] = @binary if @binary
          opts[:prefs] = @prefs unless @prefs.empty?
          opts[:log] = {level: @log_level} if @log_level

          super.merge(KEY => opts)
        end

        private

        def validate_profile
          return if @profile.is_a? Profile

          Profile.from_name(@profile)
        end
      end # Options
    end # Firefox
  end # WebDriver
end # Selenium
