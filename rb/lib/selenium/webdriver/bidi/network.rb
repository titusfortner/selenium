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
require_relative 'network/url_pattern'

module Selenium
  module WebDriver
    class BiDi
      # Implements the Navigation Module of the WebDriver-BiDi specification
      # Continue to use functionality from existing `driver.navigate` method
      #
      # @api private
      #

      class Network
        EVENTS = {
          before_request: 'network.beforeRequestSent',
          response_started: 'network.responseStarted',
          response_completed: 'network.responseCompleted',
          auth_required: 'network.authRequired',
          fetch_error: 'network.fetchError'
        }.freeze

        PHASES = {
          before_request: 'beforeRequestSent',
          response_started: 'responseStarted',
          auth_required: 'authRequired'
        }.freeze

        def initialize(bridge)
          # Resolving bridge.bidi first raises the friendly "BiDi must be enabled"
          # error on a non-BiDi bridge; it is also the event seam used by #on.
          @bidi = bridge.bidi
          @network = BiDi::Protocol::Network.new(bridge)
          @session = BiDi::Protocol::Session.new(bridge)
        end

        def add_intercept(phases: [], contexts: nil, url_patterns: nil, pattern_type: :string)
          url_patterns = url_patterns && pattern_type ? UrlPattern.format_pattern(url_patterns, pattern_type) : nil
          @network.add_intercept(phases: phases, contexts: contexts, url_patterns: url_patterns).intercept
        end

        def remove_intercept(intercept)
          @network.remove_intercept(intercept: intercept)
        end

        def continue_with_auth(request_id, username, password)
          @network.continue_with_auth(
            request: request_id,
            action: 'provideCredentials',
            credentials: Protocol::Network::AuthCredentials.new(username: username, password: password)
          )
        end

        def continue_without_auth(request_id)
          @network.continue_with_auth(request: request_id, action: 'default')
        end

        def cancel_auth(request_id)
          @network.continue_with_auth(request: request_id, action: 'cancel')
        end

        def continue_request(**args)
          @network.continue_request(
            request: args[:id],
            body: args[:body],
            cookies: args[:cookies],
            headers: args[:headers],
            method_: args[:method],
            url: args[:url]
          )
        end

        def fail_request(request_id)
          @network.fail_request(request: request_id)
        end

        def continue_response(**args)
          @network.continue_response(
            request: args[:id],
            cookies: args[:cookies],
            credentials: args[:credentials],
            headers: args[:headers],
            reason_phrase: args[:reason],
            status_code: args[:status]
          )
        end

        def provide_response(**args)
          @network.provide_response(
            request: args[:id],
            body: args[:body],
            cookies: args[:cookies],
            headers: args[:headers],
            reason_phrase: args[:reason],
            status_code: args[:status]
          )
        end

        def set_cache_behavior(behavior, *contexts)
          @network.set_cache_behavior(cache_behavior: behavior, contexts: contexts)
        end

        def on(event, &block)
          event = EVENTS[event] if event.is_a?(Symbol)
          @bidi.add_callback(event, &block)
          @session.subscribe(events: [event])
        end
      end # Network
    end # BiDi
  end # WebDriver
end # Selenium
