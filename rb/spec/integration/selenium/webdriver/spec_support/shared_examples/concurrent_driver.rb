shared_examples_for "driver that can be started concurrently" do |browser_name, driver_name|
  it "is started sequentially" do
    expect {
      Timeout.timeout(45) do
        # start 5 drivers concurrently
        threads, drivers = [], []

        5.times do
          threads << Thread.new do
            opt = driver_name ? {marionette: true} : {}
            drivers << Selenium::WebDriver.for(browser_name, opt)
          end
        end

        threads.each do |thread|
          thread.abort_on_exception = true
          thread.join
        end

        drivers.each do |driver|
          driver.title # make any wire call
          driver.quit
        end
      end
    }.not_to raise_error
  end
end
