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

require File.expand_path('../webdriver/spec_helper', __FILE__)
require 'selenium/server'

describe Selenium::Server do
  let(:mock_process) { double(ChildProcess).as_null_object }
  let(:mock_poller)  { double("SocketPoller", connected?: true, closed?: true) }

  it "raises an error if the jar file does not exist" do
    expect do
      Selenium::Server.new("doesnt-exist.jar")
    end.to raise_error(Errno::ENOENT)
  end

  it "uses the given jar file and port" do
    expect(File).to receive(:exist?).with("selenium-server-test.jar").and_return(true)

    expect(ChildProcess).to receive(:build).
                 with("java", "-jar", "selenium-server-test.jar", "-port", "1234").
                 and_return(mock_process)

    server = Selenium::Server.new("selenium-server-test.jar", port: 1234, background: true)
    allow(server).to receive(:socket).and_return(mock_poller)

    server.start
  end

  it "waits for the server process by default" do
    expect(File).to receive(:exist?).with("selenium-server-test.jar").and_return(true)

    expect(ChildProcess).to receive(:build).
                 with("java", "-jar", "selenium-server-test.jar", "-port", "4444").
                 and_return(mock_process)

    server = Selenium::Server.new("selenium-server-test.jar")
    allow(server).to receive(:socket).and_return(mock_poller)

    expect(mock_process).to receive(:wait)
    server.start
  end

  it "adds additional args" do
    expect(File).to receive(:exist?).with("selenium-server-test.jar").and_return(true)

    expect(ChildProcess).to receive(:build).
                 with("java", "-jar", "selenium-server-test.jar", "-port", "4444", "foo", "bar").
                 and_return(mock_process)

    server = Selenium::Server.new("selenium-server-test.jar", background: true)
    allow(server).to receive(:socket).and_return(mock_poller)

    server << %w(foo bar)

    server.start
  end

  it "downloads the specified version from the selenium site" do
    required_version = '10.2.0'
    expected_download_file_name = "selenium-server-standalone-#{required_version}.jar"

    stub_request(:get, "http://selenium-release.storage.googleapis.com/10.2/selenium-server-standalone-10.2.0.jar").to_return(body: "this is pretending to be a jar file for testing purposes")

    begin
      actual_download_file_name = Selenium::Server.download(required_version)
      expect(actual_download_file_name).to eq(expected_download_file_name)
      expect(File).to exist(expected_download_file_name)
    ensure
      FileUtils.rm_rf expected_download_file_name
    end
  end

  it "gets a server instance and downloads the specified version" do
    required_version = '10.4.0'
    expected_download_file_name = "selenium-server-standalone-#{required_version}.jar"
    expected_options = {port: 5555}
    fake_server = Object.new

    expect(Selenium::Server).to receive(:download).with(required_version).and_return(expected_download_file_name)
    expect(Selenium::Server).to receive(:new).with(expected_download_file_name, expected_options).and_return(fake_server)
    server = Selenium::Server.get required_version, expected_options
    expect(server).to eq(fake_server)
  end

  it "automatically repairs http_proxy settings that do not start with http://" do
    with_env("http_proxy" => "proxy.com") do
      expect(Selenium::Server.net_http.proxy_address).to eq('proxy.com')
    end

    with_env("HTTP_PROXY" => "proxy.com") do
      expect(Selenium::Server.net_http.proxy_address).to eq('proxy.com')
    end
  end

  it "only downloads a jar if it is not present in the current directory" do
    required_version = '10.2.0'
    expected_download_file_name = "selenium-server-standalone-#{required_version}.jar"

    expect(File).to receive(:exists?).with(expected_download_file_name).and_return true

    Selenium::Server.download required_version
  end

  it "should know what the latest version available is" do
    latest_version = '2.42.2'
    example_xml ="<?xml version='1.0' encoding='UTF-8'?><ListBucketResult xmlns='http://doc.s3.amazonaws.com/2006-03-01'><Name>selenium-release</Name><Contents><Key>2.39/selenium-server-2.39.0.zip</Key></Contents><Contents><Key>2.42/selenium-server-standalone-#{latest_version}.jar</Key></Contents></ListBucketResult>"
    stub_request(:get, "http://selenium-release.storage.googleapis.com/").to_return(body: example_xml)

    expect(Selenium::Server.latest).to eq(latest_version)
  end

  it "should download the latest version if that has been specified" do
    required_version = '2.42.2'
    minor_version = '2.42'

    expected_download_file_name = "selenium-server-standalone-#{required_version}.jar"

    expect(Selenium::Server).to receive(:latest).and_return required_version
    stub_request(:get, "http://selenium-release.storage.googleapis.com/#{minor_version}/#{expected_download_file_name}").to_return(body: "this is pretending to be a jar file for testing purposes")

    begin
      actual_download_file_name = Selenium::Server.download(:latest)
      expect(actual_download_file_name).to eq(expected_download_file_name)
      expect(File).to exist(expected_download_file_name)
    ensure
      FileUtils.rm_rf expected_download_file_name
    end
  end

  it "raises Selenium::Server::Error if the server is not launched within the timeout" do
    expect(File).to receive(:exist?).with("selenium-server-test.jar").and_return(true)

    poller = double('SocketPoller')
    expect(poller).to receive(:connected?).and_return(false)

    server = Selenium::Server.new("selenium-server-test.jar", background: true)
    allow(server).to receive(:socket).and_return(poller)

    expect { server.start }.to raise_error(Selenium::Server::Error)
  end

  it "sets options after instantiation" do
    expect(File).to receive(:exist?).with("selenium-server-test.jar").and_return(true)
    server = Selenium::Server.new("selenium-server-test.jar")
    expect(server.port).to eq(4444)
    expect(server.timeout).to eq(30)
    expect(server.background).to be false
    expect(server.log).to be_nil

    server.port = 1234
    server.timeout = 5
    server.background = true
    server.log = "/tmp/server.log"
  end
end
