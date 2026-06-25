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
    module Remote
      class BiDiBridge < Bridge
        # Maps the session's page load strategy to the BiDi navigation readiness
        # state used as the default `wait` for navigation commands.
        READINESS_STATE = {
          'none' => 'none',
          'eager' => 'interactive',
          'normal' => 'complete'
        }.freeze

        attr_reader :bidi, :transport

        # The websocket can only be opened once the session reports its
        # web_socket_url, so the bridge owns it from here (not injected like the HTTP
        # client). Transport is the command seam; BiDi is retained for events/session
        # over the same socket and is on its way out.
        def create_session(capabilities)
          super
          socket = WebSocketConnection.new(url: @capabilities[:web_socket_url], client_config: http.client_config)
          @transport = BiDi::Transport.new(socket)
          @bidi = BiDi.new(socket: socket, transport: @transport)
        end

        # A command a given BiDi implementation does not support raises
        # 'unknown command'; nothing executed, so it is safe to fall back to the
        # classic HTTP behavior inherited from Bridge.
        def get(url)
          browsing_context.navigate(context: window_handle, url: url, wait: readiness)
        rescue Error::UnknownCommandError
          super
        end

        def go_back
          browsing_context.traverse_history(context: window_handle, delta: -1)
        rescue Error::UnknownCommandError
          super
        end

        def go_forward
          browsing_context.traverse_history(context: window_handle, delta: 1)
        rescue Error::UnknownCommandError
          super
        end

        def refresh
          browsing_context.reload(context: window_handle, wait: readiness)
        rescue Error::UnknownCommandError
          super
        end

        def quit
          bidi.close
        rescue *QUIT_ERRORS
          nil
        ensure
          super
        end

        def close
          execute(:close_window).tap { |handles| bidi.close if handles.empty? }
        end

        private

        def browsing_context
          @browsing_context ||= BiDi::Protocol::BrowsingContext.new(self)
        end

        def readiness
          READINESS_STATE[capabilities[:page_load_strategy]]
        end
      end # BiDiBridge
    end # Remote
  end # WebDriver
end # Selenium
