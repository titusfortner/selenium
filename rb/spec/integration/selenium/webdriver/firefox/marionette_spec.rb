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
      context "when designated firefox binary includes Marionette" do
        before(:each) do
          unless ENV['MARIONETTE_PATH']
            pending "Set ENV['MARIONETTE_PATH'] to test Marionette enabled Firefox installations"
          end
        end

        compliant_on :browser => :marionette do
          it "Uses Wires when setting mariontte option in capabilities" do
            caps = Selenium::WebDriver::Remote::Capabilities.firefox(:marionette => true, :firefox_binary => ENV['MARIONETTE_PATH'])
            expect do
              @driver = Selenium::WebDriver.for :firefox, :desired_capabilities => caps
            end.to_not raise_exception
            @driver.quit
          end
        end

        compliant_on :browser => :marionette do
          it "Uses Wires when setting marionette option in driver initialization" do
            caps = Selenium::WebDriver::Remote::Capabilities.firefox(:firefox_binary => ENV['MARIONETTE_PATH'])
            @driver = Selenium::WebDriver.for :firefox, {marionette: true,
                                                         :desired_capabilities => caps}
            expect(@driver.instance_variable_get('@bridge').instance_variable_get('@launcher')).to be_nil
            @driver.quit
          end
        end

        not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1228121", :browser => :marionette do
          compliant_on :browser => :firefox do
            it "Does not use wires when marionette option is not set" do
              begin
                default_path = Firefox::Binary.path

                caps = Selenium::WebDriver::Remote::Capabilities.firefox(firefox_binary: ENV['MARIONETTE_PATH'])
                @driver = Selenium::WebDriver.for :firefox, :desired_capabilities => caps

                expect(@driver.instance_variable_get('@bridge').instance_variable_get('@launcher')).to_not be_nil
                @driver.quit
              ensure
                Firefox::Binary.path = default_path
              end
            end
          end
        end

        compliant_on :browser => :marionette do
          not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1228107", :browser => :marionette do
           it_behaves_like "driver that can be started concurrently", :marionette
          end
        end
      end

      compliant_on :browser => :firefox do
        # TODO - Adjust specs when default Firefox version includes Marionette
        context "when designated firefox binary does not include Marionette" do
          let(:message) { /Firefox Version \d\d does not support Marionette/ }

          it "Raises Wires Exception when setting mariontte option in capabilities" do
            caps = Selenium::WebDriver::Remote::Capabilities.firefox(:marionette => true)
            opt = {:desired_capabilities => caps}
            expect { Selenium::WebDriver.for :firefox, opt }.to raise_exception ArgumentError, message
          end

          it "Raises Wires Exception when setting marionette option in driver initialization" do
            expect{Selenium::WebDriver.for :firefox, {marionette: true}}.to raise_exception ArgumentError, message
          end
        end
      end
    end
  end # WebDriver
end # Selenium
