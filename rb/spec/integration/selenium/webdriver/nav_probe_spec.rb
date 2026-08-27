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

# DIAGNOSTIC (temporary): the smallest reproduction of the Windows navigation failure.
#
# The first navigation on a freshly created session aborts around 5% of the time on Windows, on any
# URL - the earlier "only fedcm.html" reading was an artifact of fedcm_spec being the only spec that
# reset per example. Classic chromedriver drops the error and answers successfully, leaving the
# browser on data:,; BiDi raises net::ERR_ABORTED for the same underlying event.
#
# The session is what is fresh, so these arms vary only what happens between creating it and asking
# it to navigate: nothing, a one second pause (what the suite already does for Safari, which is slow
# to release a previous session), or a throwaway navigation first.
#
# Delete with the rest of the diagnostic.

require_relative 'spec_helper'

module Selenium
  module WebDriver
    describe 'navigation probe', skip_unless: {browser: :chrome} do
      def landed_on(page, pause: nil, args: [])
        reset_driver!(args: args)
        sleep pause if pause
        driver.get url_for(page)
        driver.current_url
      end

      25.times do |i|
        it "navigates immediately after a reset (#{i})" do
          expect(landed_on('formPage.html')).to include('formPage.html')
        end
      end

      25.times do |i|
        it "navigates immediately with renderer task deferral disabled (#{i})" do
          expect(landed_on('formPage.html', args: ['--disable-features=DeferRendererTasksAfterInput']))
            .to include('formPage.html')
        end
      end

      25.times do |i|
        it "navigates a second after a reset (#{i})" do
          expect(landed_on('formPage.html', pause: 1)).to include('formPage.html')
        end
      end
    end
  end
end
