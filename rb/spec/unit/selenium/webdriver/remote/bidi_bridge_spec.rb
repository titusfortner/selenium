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

module Selenium
  module WebDriver
    module Remote
      describe BiDiBridge do
        let(:connection) { instance_double(WebDriver::WebSocketConnection) }
        let(:transport) { BiDi::Transport.new(connection) }
        let(:http) { instance_double(Http::Default) }
        let(:page_load_strategy) { 'normal' }
        let(:bridge) { described_class.new(http_client: http) }

        before do
          allow(bridge).to receive_messages(transport: transport, window_handle: 'win1',
                                            capabilities: {page_load_strategy: page_load_strategy})
          allow(connection).to receive(:send_cmd).and_return('result' => {})
        end

        def expect_command(method, params)
          expect(connection).to have_received(:send_cmd).with(method: method, params: params)
        end

        it 'navigates through the generated browsing context with the current handle and readiness' do
          bridge.get('https://example.com')

          expect_command('browsingContext.navigate',
                         {'context' => 'win1', 'url' => 'https://example.com', 'wait' => 'complete'})
        end

        it 'maps the page load strategy to a readiness state' do
          allow(bridge).to receive(:capabilities).and_return(page_load_strategy: 'eager')
          bridge.get('https://example.com')

          expect_command('browsingContext.navigate',
                         {'context' => 'win1', 'url' => 'https://example.com', 'wait' => 'interactive'})
        end

        context 'without a page load strategy' do
          let(:page_load_strategy) { nil }

          it 'omits wait rather than sending an explicit null' do
            bridge.get('https://example.com')

            expect_command('browsingContext.navigate',
                           {'context' => 'win1', 'url' => 'https://example.com'})
          end
        end

        it 'goes back with a negative delta' do
          bridge.go_back

          expect_command('browsingContext.traverseHistory', {'context' => 'win1', 'delta' => -1})
        end

        it 'goes forward with a positive delta' do
          bridge.go_forward

          expect_command('browsingContext.traverseHistory', {'context' => 'win1', 'delta' => 1})
        end

        it 'refreshes with the readiness state and the wire key ignoreCache omitted' do
          bridge.refresh

          expect_command('browsingContext.reload', {'context' => 'win1', 'wait' => 'complete'})
        end
      end
    end # Remote
  end # WebDriver
end # Selenium
