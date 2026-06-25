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

module Selenium
  module WebDriver
    class BiDi
      # Implements the Session Module of the WebDriver-BiDi specification
      #
      # @api private
      #
      class Session
        def initialize(transport)
          @session = Protocol::Session.new(transport)
        end

        # @return [Protocol::Session::StatusResult] responds to #ready and #message
        def status
          @session.status
        end

        def subscribe(events, browsing_contexts = nil)
          @session.subscribe(events: Array(events),
                             contexts: browsing_contexts ? Array(browsing_contexts) : UNSET)
        end

        # The BiDi unsubscribe-by-attributes request takes only events; the historical
        # browsing_contexts argument was never part of the wire shape.
        def unsubscribe(events, _browsing_contexts = nil)
          @session.unsubscribe(events: Array(events))
        end
      end # Session
    end # BiDi
  end # WebDriver
end # Selenium
