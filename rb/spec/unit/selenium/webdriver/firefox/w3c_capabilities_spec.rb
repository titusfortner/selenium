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

require File.expand_path('../../spec_helper', __FILE__)

module Selenium
  module WebDriver
    module Firefox
      describe W3CBridge do
        let(:resp) { {'sessionId' => 'foo', 'value' => @expected_capabilities.as_json} }
        let(:service) { double(Service, start: true, uri: 'http://example.com:1234') }
        let(:http) { double(Remote::Http::Default).as_null_object }
        let(:args) { [:post, "session", {desiredCapabilities: @expected_capabilities}] }

        before do
          allow(Service).to receive(:new).and_return(service)
          @expected_capabilities = Remote::W3CCapabilities.firefox
          @capabilities = Remote::W3CCapabilities.firefox
        end


        it 'accepts marionette' do
          @expected_capabilities[:marionette] = false

          allow(http).to receive(:call).with(*args).and_return(resp)
          bridge = W3CBridge.new(http_client: http, marionette: false)

          expect(bridge.capabilities.proxy).to eq proxy
        end

        it 'accepts proxy' do
          proxy = Proxy.new(http: 'localhost:1234')
          @expected_capabilities.proxy = proxy

          allow(http).to receive(:call).with(*args).and_return(resp)
          bridge = W3CBridge.new(http_client: http, proxy: proxy)

          expect(bridge.capabilities.proxy).to eq proxy
        end
      end
    end # Firefox
  end # WebDriver
end # Selenium
