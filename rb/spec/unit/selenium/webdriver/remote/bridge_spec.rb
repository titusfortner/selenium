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
    module Remote
      describe Bridge do
        let(:resp) { {'sessionId' => 'foo', 'value' => @expected_capabilities.as_json} }
        let(:http) { double(Remote::Http::Default).as_null_object }
        let(:args) { [:post, "session", {desiredCapabilities: @expected_capabilities}] }

        it 'raises ArgumentError if passed invalid options' do
          expect { Bridge.new(foo: 'bar') }.to raise_error(ArgumentError)
        end

        it 'raises WebDriverError if uploading non-files' do
          request_body = JSON.generate(sessionId: '11123', value: {})
          headers = {'Content-Type' => 'application/json'}
          stub_request(:post, 'http://127.0.0.1:4444/wd/hub/session').to_return(
              status: 200, body: request_body, headers: headers
          )

          bridge = Bridge.new
          expect { bridge.upload('NotAFile') }.to raise_error(Error::WebDriverError)
        end

        it 'respects quit_errors' do
          http_client = WebDriver::Remote::Http::Default.new
          allow(http_client).to receive(:request).and_return({'sessionId' => true, 'value' => {}})

          bridge = Bridge.new(http_client: http_client)
          allow(bridge).to receive(:execute).with(:quit).and_raise(IOError)

          expect { bridge.quit }.to_not raise_error
        end

        context 'for chrome' do
          before do
            @expected_capabilities = Remote::Capabilities.chrome
            @capabilities = Remote::Capabilities.chrome
          end

          it 'uses provided server URL' do
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'uses the default capabilities' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :chrome)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'uses capabilities constructed from parameters' do
            opts = {browser_name: 'chrome',
                    foo: 'bar',
                    'moo' => 'tar',
                    chrome_options: {'args' => %w[baz]},
                    javascript_enabled: true,
                    css_selectors_enabled: true}
            opts.each { |k, v| @expected_capabilities[k] = v }
            opts.each { |k, v| @capabilities[k] = v }

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'sets the args capability' do
            switches = ["--foo=bar"]
            @expected_capabilities.chrome_options = {'args' => switches}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, args: %w[--foo=bar], desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['args']).to eq switches
          end

          it 'lets chrome options be set by hash' do
            @expected_capabilities.chrome_options['args'] = %w[foo bar]
            @capabilities.chrome_options['args'] = %w[foo bar]

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['args']).to eq %w[foo bar]
          end

          it 'lets capabilities be set by string' do
            @expected_capabilities['chromeOptions'] = {'args' => %w[foo bar]}
            @capabilities['chromeOptions'] = {'args' => %w[foo bar]}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['args']).to eq %w[foo bar]
          end

          it 'lets direct arguments take precedence over capabilities' do
            @expected_capabilities.chrome_options = {'args' => %w[baz]}
            @capabilities.chrome_options = {'args' => %w[baz]}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities, args: %w[baz])

            expect(bridge.capabilities.chrome_options['args']).to eq %w[baz]
          end


          it 'accepts a binary location' do
            path = '/foo/chromedriver'
            @expected_capabilities.chrome_options = {'binary' => path}

            allow(Chrome).to receive(:path).and_return(path)
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['binary']).to eq path
          end

          it 'accepts args' do
            switches = ["--foo=bar"]
            @expected_capabilities.chrome_options = {'args' => switches}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, args: %w[--foo=bar], desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['args']).to eq switches
          end

          it 'accepts switches' do
            switches = ["--foo=bar"]
            @expected_capabilities.chrome_options = {'args' => switches}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, switches: %w[--foo=bar], desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['args']).to eq switches
          end

          it 'accepts profile' do
            profile = Chrome::Profile.new
            profile.add_extension(__FILE__)
            chrome_options = {'args' => ["--user-data-dir=#{profile.as_json[:directory]}"],
                              'extensions' => profile.as_json[:extensions]}
            @expected_capabilities.chrome_options = chrome_options

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, profile: profile, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options).to eq chrome_options
          end

          it 'accepts chrome detach' do
            @expected_capabilities.chrome_options = {'detach' => true}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, chrome_options: {'detach' => true}, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['detach']).to eq true
          end

          it 'accepts prefs' do
            @expected_capabilities.chrome_options = {'prefs' => {foo: 'bar'}}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, prefs: {foo: 'bar'}, desired_capabilities: @capabilities)

            expect(bridge.capabilities.chrome_options['prefs'][:foo]).to eq('bar')
          end

          it 'accepts proxy' do
            proxy = Proxy.new(http: 'localhost:1234')
            @expected_capabilities.proxy = proxy

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, proxy: proxy, desired_capabilities: @capabilities)

            expect(bridge.capabilities.proxy).to eq proxy
          end

        end

        context 'for edge' do
          before do
            @expected_capabilities = Remote::Capabilities.edge
            @capabilities = Remote::Capabilities.edge
          end

          it 'uses provided server URL' do
            expect(Service).not_to receive(:new)
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :edge)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'uses capabilities constructed from parameters' do
            opts = {browser_name: 'edge',
                    foo: 'bar',
                    'moo' => 'tar',
                    platform: 'windows',
                    takes_screenshot: true,
                    javascript_enabled: true,
                    css_selectors_enabled: true}
            opts.each { |k, v| @expected_capabilities[k] = v }
            opts.each { |k, v| @capabilities[k] = v }

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'sets the proxy capabilitiy' do
            proxy = Proxy.new(http: 'localhost:1234')
            @expected_capabilities.proxy = proxy

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, proxy: proxy, desired_capabilities: @capabilities)

            expect(bridge.capabilities.proxy).to eq proxy
          end
        end

        context 'for firefox' do
          before do
            @expected_capabilities = Remote::Capabilities.firefox
            @capabilities = Remote::Capabilities.firefox
          end

          it 'uses provided server URL' do
            expect(Service).not_to receive(:new)
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :firefox)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'uses capabilities constructed from parameters' do
            profile = Firefox::Profile.new
            opts = {browser_name: 'firefox',
                    foo: 'bar',
                    'moo' => 'tar',
                    firefox_profile: profile,
                    takes_screenshot: true,
                    javascript_enabled: true,
                    css_selectors_enabled: true}
            opts.each { |k, v| @expected_capabilities[k] = v }
            opts.each { |k, v| @capabilities[k] = v }

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'lets capabilities be set by string' do
            profile = Firefox::Profile.new
            @expected_capabilities['firefox_profile'] = profile

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @expected_capabilities)

            expect(bridge.capabilities.firefox_profile).to eq profile
          end

          it 'accepts profile' do
            profile = Firefox::Profile.new
            @expected_capabilities.firefox_profile = profile

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @expected_capabilities)

            expect(bridge.capabilities.firefox_profile).to eq profile.as_json['zip']
          end

          it 'accepts proxy' do
            proxy = Proxy.new(http: 'localhost:1234')

            @expected_capabilities.proxy = proxy
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, proxy: proxy, desired_capabilities: @capabilities)

            expect(bridge.capabilities.proxy).to eq proxy
          end

        end

        context 'for internet explorer' do
          before do
            @expected_capabilities = Remote::Capabilities.internet_explorer
            @capabilities = Remote::Capabilities.internet_explorer
          end

          it 'uses provided server URL' do
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :internet_explorer)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'sets desired capabilities by aliased symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :ie)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'uses capabilities constructed from parameters' do
            opts = {browser_name: 'ie',
                    foo: 'bar',
                    'moo' => 'tar',
                    native_events: true,
                    platform: 'windows',
                    'introduce_flakiness_by_ignoring_security_domains' => true,
                    takes_screenshot: true,
                    javascript_enabled: true,
                    css_selectors_enabled: true}
            opts.each { |k, v| @expected_capabilities[k] = v }
            opts.each { |k, v| @capabilities[k] = v }

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'lets capabilities be set by string' do
            @expected_capabilities['nativeEvents'] = true
            @capabilities['nativeEvents'] = true

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.native_events).to eq true
          end

          it 'lets direct arguments take precedence over capabilities' do
            @expected_capabilities.native_events = true
            @capabilities.native_events = false

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http,
                                desired_capabilities: @capabilities,
                                native_events: true)
            expect(bridge.capabilities.native_events).to eq true
          end

          it 'has ignore protected mode setting disabled by default' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.introduce_flakiness_by_ignoring_security_domains).to be false
          end

          it 'enables the ignore protected mode setting' do
            @expected_capabilities.ignore_protected_mode_settings = true
            @capabilities.introduce_flakiness_by_ignoring_security_domains = true

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.introduce_flakiness_by_ignoring_security_domains).to eq true
          end

          it 'has native events enabled by default' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.native_events).to be true
          end

          it 'disables native events' do
            @expected_capabilities.native_events = false

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, native_events: false, desired_capabilities: @capabilities)

            expect(bridge.capabilities.native_events).to be false
          end

          it 'sets the proxy capabilitiy' do
            proxy = Proxy.new(http: 'localhost:1234')
            @expected_capabilities.proxy = proxy

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, proxy: proxy)

            expect(bridge.capabilities.proxy).to eq proxy
          end
        end

        context 'for phantomjs' do
          before do
            @expected_capabilities = Remote::Capabilities.phantomjs
            @capabilities = Remote::Capabilities.phantomjs
          end

          it 'uses provided server URL' do
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :phantomjs)

            expect(bridge.capabilities).to eq @expected_capabilities
          end
        end

        context 'for safari' do
          before do
            @expected_capabilities = Remote::Capabilities.safari
            @capabilities = Remote::Capabilities.safari
          end

          it 'uses provided server URL' do
            expect(http).to receive(:server_url=).with(URI.parse('http://example.com:4321'))
            allow(http).to receive(:call).with(*args).and_return(resp)

            Bridge.new(http_client: http, url: 'http://example.com:4321', desired_capabilities: @capabilities)
          end

          it 'sets desired capabilities by symbol' do
            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: :safari)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'uses capabilities constructed from parameters' do
            opts = {browser_name: 'safari',
                    foo: 'bar',
                    'moo' => 'tar',
                    safari_options: {'args' => %w[baz]},
                    platform: 'mac',
                    takes_screenshot: true,
                    javascript_enabled: true,
                    css_selectors_enabled: true}
            opts.each { |k, v| @expected_capabilities[k] = v}
            opts.each { |k, v| @capabilities[k] = v}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities).to eq @expected_capabilities
          end

          it 'lets safari options be set by hash' do
            @expected_capabilities.safari_options['foo'] = 'bar'
            @capabilities.safari_options['foo'] = 'bar'

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.safari_options['foo']).to eq 'bar'
          end

          it 'lets capabilities be set by string' do
            @expected_capabilities['safari.options'] = {'args' => %w[foo bar]}
            @capabilities['safari.options'] = {'args' => %w[foo bar]}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.safari_options['args']).to eq %w[foo bar]
          end

          it 'lets direct arguments take precedence over capabilities' do
            @expected_capabilities.safari_options = {'foo' => 'bar'}
            @capabilities.safari_options = {'foo' => 'bar'}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities, safari_options: {'foo' => 'bar'})

            expect(bridge.capabilities.safari_options['foo']).to eq 'bar'
          end

          it 'accepts technology preview' do
            @expected_capabilities.safari_options = {'technologyPreview' => true}
            @capabilities.safari_options = {'technologyPreview' => true}

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, desired_capabilities: @capabilities)

            expect(bridge.capabilities.technology_preview).to eq true
          end

          it 'accepts proxy' do
            proxy = Proxy.new(http: 'localhost:1234')
            @expected_capabilities.proxy = proxy

            allow(http).to receive(:call).with(*args).and_return(resp)
            bridge = Bridge.new(http_client: http, proxy: proxy, desired_capabilities: @capabilities)

            expect(bridge.capabilities.proxy).to eq proxy
          end
        end
      end
    end # Remote
  end # WebDriver
end # Selenium
