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
%w[serialization browsing_context script network].each do |file|
  require File.expand_path("../../../../../lib/selenium/webdriver/bidi/protocol/#{file}", __dir__)
end

module Selenium
  module WebDriver
    class BiDi
      module Protocol
        describe 'generated structured types' do
          describe 'a record with a baked discriminator' do
            it 'round-trips through the wire' do
              locator = BrowsingContext::CssLocator.new(value: '.foo')

              expect(locator.to_wire).to eq('type' => 'css', 'value' => '.foo')
              expect(BrowsingContext::CssLocator.from_wire(locator.to_wire)).to eq(locator)
            end

            it 'raises when a required field is missing' do
              expect { BrowsingContext::CssLocator.new }.to raise_error(ArgumentError, /value/)
            end
          end

          describe 'discriminated union dispatch' do
            it 'selects the variant by its discriminator value' do
              parsed = BrowsingContext::Locator.from_wire('type' => 'css', 'value' => '.x')

              expect(parsed).to be_a(BrowsingContext::CssLocator)
              expect(parsed.value).to eq('.x')
            end

            it 'selects a variant by which fields are present when there is no discriminator' do
              parsed = Script::RemoteReference.from_wire('sharedId' => 'abc')

              expect(parsed).to be_a(Script::SharedReference)
              expect(parsed.shared_id).to eq('abc')
            end

            it 'dispatches the LocalValue date and regexp variants restored upstream' do
              expect(Script::LocalValue.from_wire('type' => 'date', 'value' => '2026-01-01'))
                .to be_a(Script::DateLocalValue)
              expect(Script::LocalValue.from_wire('type' => 'regexp', 'value' => {'pattern' => 'ab+c'}))
                .to be_a(Script::RegExpLocalValue)
            end
          end

          describe 'nested structured fields' do
            let(:cookie) do
              Network::Cookie.new(
                name: 'sid', value: Network::StringValue.new(value: 'YQ=='),
                domain: 'example.com', path: '/', size: 3,
                http_only: false, secure: true, same_site: 'none'
              )
            end

            it 'serializes a nested value object into its wire hash' do
              expect(cookie.to_wire).to include('value' => {'type' => 'string', 'value' => 'YQ=='})
            end

            it 'parses a nested wire hash back into the value object' do
              parsed = Network::Cookie.from_wire(cookie.to_wire)

              expect(parsed.value).to eq(Network::StringValue.new(value: 'YQ=='))
              expect(parsed).to eq(cookie)
            end
          end

          describe 'recursive structured types' do
            it 'round-trips a nested LocalValue tree through the union dispatcher' do
              inner = Script::ArrayLocalValue.new(value: [Script::StringValue.new(value: 'x')])
              outer = Script::ArrayLocalValue.new(value: [Script::NumberValue.new(value: 1), inner])

              expect(outer.to_wire).to eq(
                'type' => 'array',
                'value' => [
                  {'type' => 'number', 'value' => 1},
                  {'type' => 'array', 'value' => [{'type' => 'string', 'value' => 'x'}]}
                ]
              )
              expect(Script::LocalValue.from_wire(outer.to_wire)).to eq(outer)
            end
          end

          describe 'optional + nullable fields' do
            it 'omits an unset field but emits explicit null for a nullable one' do
              omitted = BrowsingContext::SetViewportParameters.new(context: 'c')
              explicit = BrowsingContext::SetViewportParameters.new(context: 'c', device_pixel_ratio: nil)

              expect(omitted.to_wire).to eq('context' => 'c')
              expect(explicit.to_wire).to eq('context' => 'c', 'devicePixelRatio' => nil)
            end
          end

          describe 'extensible records' do
            it 'captures unknown keys and merges them back on serialization' do
              parsed = Script::SharedReference.from_wire('sharedId' => 's1', 'webdriverValue' => 42)

              expect(parsed.shared_id).to eq('s1')
              expect(parsed.extensions).to eq('webdriverValue' => 42)
              expect(parsed.to_wire).to eq('sharedId' => 's1', 'webdriverValue' => 42)
            end
          end

          describe 'a command parsing its result' do
            it 'returns the typed result object' do
              bidi = instance_double(BiDi)
              allow(bidi).to receive(:send_cmd).and_return('navigation' => 'n1', 'url' => 'https://x')

              result = BrowsingContext.new(bidi).navigate(context: 'c', url: 'https://x')

              expect(result).to be_a(BrowsingContext::NavigateResult)
              expect(result.url).to eq('https://x')
              expect(result.navigation).to eq('n1')
            end
          end
        end
      end # Protocol
    end # BiDi
  end # WebDriver
end # Selenium
