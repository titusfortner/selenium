# frozen_string_literal: true

# DIAGNOSTIC (temporary): the smallest reproduction of the Windows navigation failure.
#
# chromedriver's own log shows Page.navigate coming back with errorText net::ERR_ABORTED while
# chromedriver still answers RESPONSE Navigate successfully, leaving the browser on data:,. Every
# observed case was the first navigation on a session created moments earlier, and every one was
# fedcm.html — but fedcm_spec is the only spec that resets per example, so those two have never been
# separated. These contexts vary one thing at a time.
#
# Delete with the rest of the diagnostic.

require_relative 'spec_helper'

module Selenium
  module WebDriver
    describe 'navigation probe', skip_unless: {browser: :chrome} do
      def landed_on(page, prime: nil)
        reset_driver!
        driver.get url_for(prime) if prime
        driver.get url_for(page)
        driver.current_url
      end

      25.times do |i|
        it "fedcm.html as the first navigation (#{i})" do
          expect(landed_on('fedcm/fedcm.html')).to include('fedcm.html')
        end
      end

      25.times do |i|
        it "fedcm.html after priming with blank.html (#{i})" do
          expect(landed_on('fedcm/fedcm.html', prime: 'blank.html')).to include('fedcm.html')
        end
      end

      25.times do |i|
        it "formPage.html as the first navigation (#{i})" do
          expect(landed_on('formPage.html')).to include('formPage.html')
        end
      end
    end
  end
end
