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

require File.expand_path('../spec_helper', __dir__)
require File.expand_path('../../../../../lib/selenium/webdriver/bidi/protocol', __dir__)

module Selenium
  module WebDriver
    class BiDi
      describe Transport do
        let(:connection) { instance_double(WebDriver::WebSocketConnection) }
        let(:transport) { described_class.new(connection) }

        def stub_result(result = {})
          allow(connection).to receive(:send_cmd).and_return('result' => result)
        end

        it 'sends the method/params envelope and returns the raw result by default' do
          stub_result('handle' => 'h1')

          expect(transport.execute('script.evaluate', {expression: '1'})).to eq('handle' => 'h1')
          expect(connection).to have_received(:send_cmd)
            .with(method: 'script.evaluate', params: {expression: '1'})
        end

        it 'drops omitted (nil / UNSET) params from the payload' do
          stub_result

          transport.execute('browser.setDownloadBehavior', {downloadBehavior: 'b', userContexts: nil, x: UNSET})

          expect(connection).to have_received(:send_cmd)
            .with(method: 'browser.setDownloadBehavior', params: {downloadBehavior: 'b'})
        end

        it 'serializes NULL to an explicit wire null' do
          stub_result

          transport.execute('browser.setDownloadBehavior', {downloadBehavior: NULL})

          expect(connection).to have_received(:send_cmd)
            .with(method: 'browser.setDownloadBehavior', params: {downloadBehavior: nil})
        end

        it 'renders a generated value object to its wire shape' do
          stub_result

          transport.execute('storage.setCookie', {value: Protocol::Network::StringValue.new(value: 'YQ==')})

          expect(connection).to have_received(:send_cmd)
            .with(method: 'storage.setCookie', params: {value: {'type' => 'string', 'value' => 'YQ=='}})
        end

        it 'parses the result into the declared value type' do
          stub_result('navigation' => 'n1', 'url' => 'https://x')

          result = transport.execute('browsingContext.navigate', {context: 'c'},
                                     returns: Protocol::BrowsingContext::NavigateResult)

          expect(result).to be_a(Protocol::BrowsingContext::NavigateResult)
          expect(result.url).to eq('https://x')
        end

        it 'raises on an error reply' do
          allow(connection).to receive(:send_cmd)
            .and_return('error' => 'no such frame', 'message' => 'gone', 'stacktrace' => '')

          expect { transport.execute('browsingContext.navigate', {context: 'c'}) }
            .to raise_error(Error::WebDriverError, /no such frame/)
        end
      end
    end # BiDi
  end # WebDriver
end # Selenium
