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

require_relative 'spec_helper'

describe "Selenium::WebDriver::TargetLocator" do

  let(:new_window) { driver.window_handles.find { |handle| handle != driver.window_handle } }

  not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=805475", :browser => :marionette do
    it "should find the active element" do
      driver.navigate.to url_for("xhtmlTest.html")
      expect(driver.switch_to.active_element).to be_an_instance_of(WebDriver::Element)
    end
  end

  it "should switch to a frame directly" do
    driver.navigate.to url_for("iframes.html")
    driver.switch_to.frame("iframe1")

    expect(driver.find_element(:name, 'login')).to be_kind_of(WebDriver::Element)
  end

  it "should switch to a frame by Element" do
    driver.navigate.to url_for("iframes.html")

    iframe = driver.find_element(:tag_name => "iframe")
    driver.switch_to.frame(iframe)

    expect(driver.find_element(:name, 'login')).to be_kind_of(WebDriver::Element)
  end

  not_compliant_on "Parent Frame implemented after driver out of active development", :browser => [:phantomjs, :safari] do
    it "should switch to parent frame" do
      # For some reason Marionette loses control of itself here unless reset. Unable to isolate
      compliant_on :driver => :marionette do
        reset_driver!
      end
      driver.navigate.to url_for("iframes.html")

      iframe = driver.find_element(:tag_name => "iframe")
      driver.switch_to.frame(iframe)

      expect(driver.find_element(:name, 'login')).to be_kind_of(WebDriver::Element)

      driver.switch_to.parent_frame
      expect(driver.find_element(:id, 'iframe_page_heading')).to be_kind_of(WebDriver::Element)
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    it "should switch to a window and back when given a block" do
      driver.navigate.to url_for("xhtmlTest.html")

      driver.find_element(:link, "Open new window").click
      expect(driver.title).to eq("XHTML Test Page")

      driver.switch_to.window(new_window) do
        wait.until { driver.title == "We Arrive Here" }
      end

      wait.until { driver.title == "XHTML Test Page" }
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    it "should handle exceptions inside the block" do
      driver.navigate.to url_for("xhtmlTest.html")

      driver.find_element(:link, "Open new window").click
      expect(driver.title).to eq("XHTML Test Page")

      expect {
        driver.switch_to.window(new_window) { raise "foo" }
      }.to raise_error(RuntimeError, "foo")

      expect(driver.title).to eq("XHTML Test Page")
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    it "should switch to a window without a block" do
      driver.navigate.to url_for("xhtmlTest.html")

      driver.find_element(:link, "Open new window").click
      expect(driver.title).to eq("XHTML Test Page")

      driver.switch_to.window(new_window)
      expect(driver.title).to eq("We Arrive Here")
      ensure_single_window
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    it "should use the original window if the block closes the popup" do
      driver.navigate.to url_for("xhtmlTest.html")

      driver.find_element(:link, "Open new window").click
      expect(driver.title).to eq("XHTML Test Page")

      driver.switch_to.window(new_window) do
        wait.until { driver.title == "We Arrive Here" }
        driver.close
      end

      expect(driver.current_url).to include("xhtmlTest.html")
      expect(driver.title).to eq("XHTML Test Page")
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1128656", {:driver => :marionette,
                                                                              :platform => [:macosx, :linux]} do
      it "should close current window when more than two windows exist" do
        driver.navigate.to url_for("xhtmlTest.html")
        driver.find_element(:link, "Create a new anonymous window").click
        wait.until { driver.window_handles.size == 2 }
        driver.find_element(:link, "Open new window").click
        wait.until { driver.window_handles.size == 3 }

        driver.switch_to.window(driver.window_handle) { driver.close }
        expect(driver.window_handles.size).to eq 2
        ensure_single_window
      end
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1128656", {:driver => :marionette,
                                                                              :platform => [:macosx, :linux]} do
      it "should close another window when more than two windows exist" do
        driver.navigate.to url_for("xhtmlTest.html")
        driver.find_element(:link, "Create a new anonymous window").click
        wait.until { driver.window_handles.size == 2 }
        driver.find_element(:link, "Open new window").click
        wait.until { driver.window_handles.size == 3 }

        window_to_close = driver.window_handles.last

        driver.switch_to.window(window_to_close) { driver.close }
        expect(driver.window_handles.size).to eq 2
        ensure_single_window
      end
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1128656", {:driver => :marionette,
                                                                              :platform => [:macosx, :linux]} do
      it "should iterate over open windows when current window is not closed" do
        driver.navigate.to url_for("xhtmlTest.html")
        driver.find_element(:link, "Create a new anonymous window").click
        wait.until { driver.window_handles.size == 2 }
        driver.find_element(:link, "Open new window").click
        wait.until { driver.window_handles.size == 3 }

        matching_window = driver.window_handles.find do |wh|
          driver.switch_to.window(wh) { driver.title == "We Arrive Here" }
        end

        driver.switch_to.window(matching_window)
        expect(driver.title).to eq("We Arrive Here")
        ensure_single_window
      end
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1128656", {:driver => :marionette,
                                                                              :platform => [:macosx, :linux]} do
      it "should iterate over open windows when current window is closed" do
        driver.navigate.to url_for("xhtmlTest.html")
        driver.find_element(:link, "Create a new anonymous window").click
        wait.until { driver.window_handles.size == 2 }
        driver.find_element(:link, "Open new window").click
        wait.until { driver.window_handles.size == 3 }

        driver.close

        matching_window = driver.window_handles.find do |wh|
          driver.switch_to.window(wh) { driver.title == "We Arrive Here" }
        end

        driver.switch_to.window(matching_window)
        expect(driver.title).to eq("We Arrive Here")
        ensure_single_window
      end
    end
  end

  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1241", {:driver => :remote,
                                                                          :browser => :marionette} do
    it "should switch to a window and execute a block when current window is closed" do
      driver.navigate.to url_for("xhtmlTest.html")
      driver.find_element(:link, "Open new window").click
      wait.until { driver.window_handles.size == 2 }

      driver.switch_to.window(new_window)
      wait.until { driver.title == "We Arrive Here" }

      driver.close

      driver.switch_to.window(driver.window_handles.first) do
        wait.until { driver.title == "XHTML Test Page" }
      end

      expect(driver.title).to eq("XHTML Test Page")
    end
  end

  it "should switch to default content" do
    driver.navigate.to url_for("iframes.html")

    driver.switch_to.frame 0
    driver.switch_to.default_content

    driver.find_element(:id => "iframe_page_heading")
  end


  not_compliant_on "https://github.com/SeleniumHQ/selenium/issues/1242", {:driver => :remote,
                                                                          :browser => :marionette} do
    not_compliant_on "http://github.com/detro/ghostdriver/issues/20", {:browser => :phantomjs} do
      not_compliant_on "http://code.google.com/p/selenium/issues/detail?id=3862", {:browser => :safari} do
        describe "alerts" do
          it "allows the user to accept an alert" do
            driver.navigate.to url_for("alerts.html")
            driver.find_element(:id => "alert").click

            alert = wait_for_alert
            alert.accept

            expect(driver.title).to eq("Testing Alerts")
          end

          not_compliant_on "https://code.google.com/p/chromedriver/issues/detail?id=26", {:browser => :chrome,
                                                                                          :platform => :macosx} do
            it "allows the user to dismiss an alert" do
              driver.navigate.to url_for("alerts.html")
              driver.find_element(:id => "alert").click

              alert = wait_for_alert
              alert.dismiss

              wait_for_no_alert

              expect(driver.title).to eq("Testing Alerts")
            end
          end

          # TODO - File Marionette Bug
          not_compliant_on "Marionette Error: keysToSend.join is not a function", {:driver => :marionette,
                                                                                   :platform => [:macosx, :linux]} do
            it "allows the user to set the value of a prompt" do
              driver.navigate.to url_for("alerts.html")
              driver.find_element(:id => "prompt").click

              alert = wait_for_alert
              alert.send_keys "cheese"
              alert.accept

              text = driver.find_element(:id => "text").text
              expect(text).to eq("cheese")
            end
          end

          it "allows the user to get the text of an alert" do
            driver.navigate.to url_for("alerts.html")
            driver.find_element(:id => "alert").click

            alert = wait_for_alert
            text = alert.text
            alert.accept

            expect(text).to eq("cheese")
          end

          it "raises when calling #text on a closed alert" do
            driver.navigate.to url_for("alerts.html")
            driver.find_element(:id => "alert").click

            alert = wait_for_alert
            alert.accept

            expect { alert.text }.to raise_error(Selenium::WebDriver::Error::NoSuchAlertError)
          end

          it "raises NoAlertOpenError if no alert is present" do
            expect { driver.switch_to.alert }.to raise_error(Selenium::WebDriver::Error::NoSuchAlertError, /alert|modal/i)
          end

          not_compliant_on "https://bugzilla.mozilla.org/show_bug.cgi?id=1206126", {:driver => :marionette} do
            it "raises an UnhandledAlertError if an alert has not been dealt with" do
              driver.navigate.to url_for("alerts.html")
              driver.find_element(:id => "alert").click
              wait_for_alert

              expect { driver.title }.to raise_error(Selenium::WebDriver::Error::UnhandledAlertError)
              reset_driver!
            end
          end
        end
      end
    end
  end
end
