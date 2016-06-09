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

require_relative '../spec_helper'

module Selenium
  module WebDriver
    describe Firefox do
      def restart_remote_server
        server = GlobalTestEnv.reset_remote_server
        server.start
        server.webdriver_url
      end

      before(:all) do
        driver
        quit_driver
      end

      before do
        @opt = {}
        @opt[:url] = restart_remote_server if GlobalTestEnv.driver == :remote
      end

      compliant_on browser: :marionette do
        it "creates default capabilities" do
          begin
            @opt[:marionette] = true
            driver1 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt
            expect(driver1.capabilities.browser_version).to match(/^\d\d\./)
            expect(driver1.capabilities.platform_name).to_not be_nil
            expect(driver1.capabilities.platform_version).to_not be_nil
            expect(driver1.capabilities.accept_ssl_certs).to be == false
            expect(driver1.capabilities.page_load_strategy).to be == 'normal'
            expect(driver1.capabilities.proxy).to be_nil
            if GlobalTestEnv.driver == :remote
              expect(driver1.capabilities.remote_session_id).to match(/^\h{8}-\h{4}-\h{4}-\h{4}-\h{10}/)
            else
              expect(driver1.capabilities.remote_session_id).to be_nil
            end
            expect(driver1.capabilities.raise_accessibility_exceptions).to be == false
            expect(driver1.capabilities.rotatable).to be == false
          ensure
            driver1.quit
          end
        end

        not_compliant_on driver: :remote do
          it "takes a binary path as an argument" do
            pending "Set ENV['ALT_MARIONETTE_BINARY'] to test this" unless ENV['ALT_MARIONETTE_BINARY']

            begin
              @opt[:marionette] = true
              driver1 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt

              default_version = driver1.capabilities.version
              expect { driver1.capabilities.browser_version }.to_not raise_exception NoMethodError
              driver1.quit

              caps = Remote::Capabilities.firefox(firefox_binary: ENV['ALT_MARIONETTE_BINARY'])
              @opt[:desired_capabilities] = caps
              driver2 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt

              expect(driver2.capabilities.version).to_not eql(default_version)
              expect { driver2.capabilities.browser_version }.to_not raise_exception NoMethodError
              driver2.quit
            ensure
              Firefox::Binary.reset_path!
            end
          end
        end
      end

      compliant_on browser: :marionette do
        it "Uses geckodriver when setting marionette option in capabilities" do
          caps = Selenium::WebDriver::Remote::Capabilities.firefox(marionette: true)
          @opt[:desired_capabilities] = caps
          expect { @driver1 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt }.to_not raise_exception
          @driver1.quit
        end

        compliant_on browser: :marionette do
          # This passes in isolation, but can not run in suite due to combination of
          # https://bugzilla.mozilla.org/show_bug.cgi?id=1228107 & https://github.com/SeleniumHQ/selenium/issues/1150
          it "Uses Wires when setting marionette option in driver initialization" do
            @opt[:marionette] = true
            driver1 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt

            expect(driver1.capabilities[:browser_version]).to_not be_nil
            driver1.quit
          end
        end

        # test with firefox due to https://bugzilla.mozilla.org/show_bug.cgi?id=1228121
        compliant_on browser: :firefox do
          it "Does not use geckodriver when marionette option is not set" do
            driver1 = Selenium::WebDriver.for GlobalTestEnv.driver, @opt

            expect { driver1.capabilities.browser_version }.to raise_exception NoMethodError
            driver1.quit
          end
        end

        compliant_on driver: :marionette do
          # https://github.com/mozilla/geckodriver/issues/58
          not_compliant_on driver: :marionette do
            context 'when shared example' do
              before { driver }
              it_behaves_like "driver that can be started concurrently", :marionette
            end
          end
        end
      end
    end # Firefox
  end # WebDriver
end # Selenium
