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

require 'timeout'
require 'socket'
require 'rexml/document'

module Selenium
  module WebDriver
    module Firefox
      autoload :Extension, 'selenium/webdriver/firefox/extension'
      autoload :ProfilesIni, 'selenium/webdriver/firefox/profiles_ini'
      autoload :Profile, 'selenium/webdriver/firefox/profile'
      autoload :Features, 'selenium/webdriver/firefox/features'
      autoload :Driver, 'selenium/webdriver/firefox/driver'
      autoload :Options, 'selenium/webdriver/firefox/options'
      autoload :Service, 'selenium/webdriver/firefox/service'

      DEFAULT_PORT = 7055
      DEFAULT_ENABLE_NATIVE_EVENTS = Platform.os == :windows
      DEFAULT_SECURE_SSL = false
      DEFAULT_ASSUME_UNTRUSTED_ISSUER = true
      DEFAULT_LOAD_NO_FOCUS_LIB = false

      def self.driver_path=(path)
        WebDriver.logger.deprecate 'Selenium::WebDriver::Firefox#driver_path=',
                                   'Selenium::WebDriver::Firefox::Service#driver_path=',
                                   id: :driver_path
        Selenium::WebDriver::Firefox::Service.driver_path = path
      end

      def self.driver_path
        WebDriver.logger.deprecate 'Selenium::WebDriver::Firefox#driver_path',
                                   'Selenium::WebDriver::Firefox::Service#driver_path',
                                   id: :driver_path
        Selenium::WebDriver::Firefox::Service.driver_path
      end

      def self.path=(path)
        Platform.assert_executable path
        @path = path
      end

      def self.path
        @path ||= nil
      end
    end # Firefox
  end # WebDriver
end # Selenium
