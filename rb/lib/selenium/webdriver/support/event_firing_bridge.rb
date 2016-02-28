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
    module Support

      #
      # @api private
      #

      class EventFiringBridge
        def initialize(delegate, listener)
          @delegate = delegate

          if listener.respond_to? :call
            @listener = BlockEventListener.new(listener)
          else
            @listener = listener
          end
        end

        def get(url)
          dispatch(:navigate_to, url, driver) {
            @delegate.get(url)
          }
        end

        def goForward
          dispatch(:navigate_forward, driver) {
            @delegate.goForward
          }
        end

        def goBack
          dispatch(:navigate_back, driver) {
            @delegate.goBack
          }
        end

        def clickElement(ref)
          dispatch(:click, create_element(ref), driver) {
            @delegate.clickElement(ref)
          }
        end

        def clearElement(ref)
          dispatch(:change_value_of, create_element(ref), driver) {
            @delegate.clearElement(ref)
          }
        end

        def sendKeysToElement(ref, keys)
          dispatch(:change_value_of, create_element(ref), driver) {
            @delegate.sendKeysToElement(ref, keys)
          }
        end

        def find_element_by(how, what, parent = nil)
          e = dispatch(:find, how, what, driver) {
            @delegate.find_element_by how, what, parent
          }

          Element.new self, e.ref
        end

        def find_elements_by(how, what, parent = nil)
          es = dispatch(:find, how, what, driver) {
            @delegate.find_elements_by(how, what, parent)
          }

          es.map { |e| Element.new self, e.ref }
        end

        def executeScript(script, *args)
          dispatch(:execute_script, script, driver) {
            @delegate.executeScript(script, *args)
          }
        end

        def quit
          dispatch(:quit, driver) { @delegate.quit }
        end

        def close
          dispatch(:close, driver) { @delegate.close }
        end

        private

        def create_element(ref)
          # hmm. we're not passing self here to not fire events for potential calls made by the listener
          Element.new @delegate, ref
        end

        def driver
          @driver ||= Driver.new(self)
        end

        def dispatch(name, *args, &_blk)
          @listener.__send__("before_#{name}", *args)
          returned = yield
          @listener.__send__("after_#{name}", *args)

          returned
        end

        def method_missing(meth, *args, &blk)
          @delegate.__send__(meth, *args, &blk)
        end
      end # EventFiringBridge

    end # Support
  end # WebDriver
end # Selenium
