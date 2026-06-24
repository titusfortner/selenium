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

        it 'serializes a params object and returns the raw result by default' do
          stub_result('handle' => 'h1')
          params = Protocol::Browser::CreateUserContextParameters.new(accept_insecure_certs: true)

          expect(transport.execute('browser.createUserContext', params)).to eq('handle' => 'h1')
          expect(connection).to have_received(:send_cmd)
            .with(method: 'browser.createUserContext', params: {'acceptInsecureCerts' => true})
        end

        it 'parses the result into the declared type' do
          stub_result('navigation' => 'n1', 'url' => 'https://x')
          params = Protocol::BrowsingContext::NavigateParameters.new(context: 'c', url: 'https://x')

          result = transport.execute('browsingContext.navigate', params, Protocol::BrowsingContext::NavigateResult)

          expect(result).to be_a(Protocol::BrowsingContext::NavigateResult)
          expect(result.url).to eq('https://x')
        end

        it 'sends an empty payload when there are no params' do
          stub_result
          transport.execute('browser.close')
          expect(connection).to have_received(:send_cmd).with(method: 'browser.close', params: {})
        end

        it 'drops omitted entries from a passthrough hash' do
          stub_result
          transport.execute('session.unsubscribe', {events: ['log.entryAdded'], subscriptions: nil})
          expect(connection).to have_received(:send_cmd)
            .with(method: 'session.unsubscribe', params: {events: ['log.entryAdded']})
        end

        it 'raises on an error reply' do
          allow(connection).to receive(:send_cmd)
            .and_return('error' => 'no such frame', 'message' => 'gone', 'stacktrace' => '')

          expect { transport.execute('browsingContext.navigate') }
            .to raise_error(Error::NoSuchFrameError, /no such frame/)
        end

        it 'maps a BiDi error code to its typed exception' do
          allow(connection).to receive(:send_cmd)
            .and_return('error' => 'unknown command', 'message' => 'nope', 'stacktrace' => '')

          expect { transport.execute('browsingContext.navigate') }
            .to raise_error(Error::UnknownCommandError, /unknown command/)
        end

        describe '.for' do
          it 'resolves a Transport, a bridge, and a driver to the transport' do
            bridge = instance_double(Remote::BiDiBridge, transport: transport)
            driver = instance_double(Driver)
            allow(driver).to receive(:bridge).and_return(bridge) # private on the real Driver

            expect(described_class.for(transport)).to be(transport)
            expect(described_class.for(bridge)).to be(transport)
            expect(described_class.for(driver)).to be(transport)
          end
        end
      end
    end # BiDi
  end # WebDriver
end # Selenium
