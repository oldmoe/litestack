require "minitest/autorun"
require "../lib/litestack/litejob"

# create a job queue (will be saved in a class variable)
Litejobqueue.new({retries: 3, retry_delay: 1, retry_delay_multiplier: 1, gc_sleep_interval: 1, dead_job_retention: 1, logger: "STDOUT"})

class MyJob
  include Litejob

  @@attempts = {}

  def perform(name, time)
    if @@attempts[name]
      @@attempts[name] += 1
    else
      @@attempts[name] = 1
    end
    puts "Job: #{name}: attempt #{@@attempts[name]}"
    raise "some error" if Time.now.to_i < time
    puts "Job: #{name}: finished"
  end
end

# this job will fail forever
MyJob.perform_async("FAILURE", Time.now.to_i + 10)

# this job will fail two times
MyJob.perform_async("EVENTUAL SUCCESS", Time.now.to_i + 2)

# this job will never fail
MyJob.perform_async("SUCCESS", Time.now.to_i)

sleep
