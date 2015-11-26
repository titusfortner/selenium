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

require 'rubygems'
require 'time'
require 'rspec'
require 'ci/reporter/rspec'

require 'selenium-webdriver'
require_relative 'spec_support'

include Selenium

GlobalTestEnv = WebDriver::SpecSupport::TestEnvironment.new

class Object
  include WebDriver::SpecSupport::Guards
end

RSpec.configure do |c|
  c.include(WebDriver::SpecSupport::Helpers)
  c.before(:suite) do
    if GlobalTestEnv.browser == :marionette
      @default_path = Selenium::WebDriver::Firefox::Binary.path
      Selenium::WebDriver::Firefox::Binary.path = ENV['MARIONETTE_PATH']
    end

    if GlobalTestEnv.driver == :remote && !ENV['SAUCE_USERNAME']
      server = GlobalTestEnv.remote_server
      if GlobalTestEnv.browser == :marionette
        server << "-Dwebdriver.firefox.bin=#{ENV['MARIONETTE_PATH']}"
      end
      server.start
    elsif GlobalTestEnv.driver == :remote
      require 'sauce'
      ENV['WD_REMOTE_URL'] = "http://#{ENV['SAUCE_USERNAME']}:#{ENV['SAUCE_ACCESS_KEY']}@ondemand.saucelabs.com:80/wd/hub"
    end
  end

  c.after(:each) do
    @exception ||= !RSpec.current_example.exception.nil?
  end

  c.after(:suite) do
    Selenium::WebDriver::Firefox::Binary.path = @default_path if GlobalTestEnv.browser == :marionette
    SauceWhisk::Jobs.change_status(driver.session_id, !@exception) if ENV['SAUCE_USERNAME']
    GlobalTestEnv.quit_driver
  end

  c.filter_run :focus => true if ENV['focus']
end

WebDriver::Platform.exit_hook { GlobalTestEnv.quit }

$stdout.sync = true
GlobalTestEnv.unguarded = !!ENV['noguards']
WebDriver::SpecSupport::Guards.print_env
