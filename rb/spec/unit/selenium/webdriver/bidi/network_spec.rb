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
    class BiDi
      describe Network do
        let(:connection) { instance_double(WebDriver::WebSocketConnection) }
        let(:transport) { Transport.new(connection) }
        let(:bridge) { instance_double(Remote::BiDiBridge, transport: transport, bidi: instance_double(BiDi)) }
        let(:network) { described_class.new(bridge) }
        let(:request_id) { '12345-request-id' }

        before { allow(connection).to receive(:send_cmd).and_return('result' => {}) }

        def expect_command(method, params)
          expect(connection).to have_received(:send_cmd).with(method: method, params: params)
        end

        describe '#continue_request' do
          it 'sends only the mandatory request ID when all optional args are nil' do
            network.continue_request(id: request_id)

            expect_command('network.continueRequest', {'request' => request_id})
          end

          it 'sends only provided optional args and maps method to its wire key' do
            network.continue_request(
              id: request_id,
              body: {type: 'string', value: 'new body'},
              cookies: nil,
              headers: nil,
              method: 'POST'
            )

            expect_command('network.continueRequest',
                           {'request' => request_id, 'body' => {type: 'string', value: 'new body'}, 'method' => 'POST'})
          end
        end

        describe '#continue_response' do
          it 'sends only the mandatory request ID when all optional args are nil' do
            network.continue_response(id: request_id)

            expect_command('network.continueResponse', {'request' => request_id})
          end

          it 'sends only provided optional args and maps status to statusCode' do
            headers = [{name: 'Auth', value: {type: 'string', value: 'Token'}}]

            network.continue_response(
              id: request_id,
              cookies: nil,
              credentials: nil,
              headers: headers,
              reason: nil,
              status: 202
            )

            expect_command('network.continueResponse',
                           {'request' => request_id, 'headers' => headers, 'statusCode' => 202})
          end
        end

        describe '#provide_response' do
          it 'sends only the mandatory request ID when all optional args are nil' do
            network.provide_response(id: request_id)

            expect_command('network.provideResponse', {'request' => request_id})
          end

          it 'sends only provided optional args and maps reason to reasonPhrase' do
            network.provide_response(
              id: request_id,
              body: {type: 'string', value: 'Hello'},
              cookies: nil,
              headers: nil,
              reason: 'OK-Custom',
              status: nil
            )

            expect_command('network.provideResponse',
                           {'request' => request_id,
                            'body' => {type: 'string', value: 'Hello'},
                            'reasonPhrase' => 'OK-Custom'})
          end
        end

        describe '#continue_with_auth' do
          it 'builds the provideCredentials action with password credentials' do
            network.continue_with_auth(request_id, 'user', 'pass')

            expect_command('network.continueWithAuth',
                           {'request' => request_id, 'action' => 'provideCredentials',
                            'credentials' => {type: 'password', username: 'user', password: 'pass'}})
          end
        end
      end
    end
  end
end
