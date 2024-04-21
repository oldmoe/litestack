require "minitest/autorun"
require 'active_job'
require_relative "../lib/litestack/litejobqueue"

ActiveJob::Base.logger = Logger.new(IO::NULL)

$ljq = nil

class Job < ActiveJob::Base

  queue_as :test
  
  SINK = {}

  def self.sink
    SINK
  end
    
  def perform(key, time)
    #puts "called with #{key} and time = #{time}. time now is #{Time.now}"
    #puts caller
    SINK[key] = true
  end
  
end

class TestLitejobRails < Minitest::Test
    
  def setup
    if $ljq.nil?
      require_relative "../lib/litestack/litejobqueue"
      $ljq = Litejobqueue.jobqueue(path: ":memory:", retries: 1, retry_delay: 1, retry_delay_multiplier: 1, sleep_intervals: [0.01], queues: [["test", 1]], logger: nil)
      require_relative "../lib/active_job/queue_adapters/litejob_adapter"
      Job.queue_adapter = :litejob
      sleep 0.1
    end
  end

  def teardown
  end
  
  def test_job_is_peformed_now
    assert Job.perform_now(:now, Time.now)
    assert Job.sink[:now]
  end
  
  def test_job_is_performed_later
    Job.perform_later(:later, Time.now)
    assert Job.sink[:later] == nil
    wait_for(Job.sink[:later].nil?, 1.0)
    assert Job.sink[:later]
  end
  
  def test_job_is_performed_after_one_second
    Job.set(wait: 1.seconds).perform_later(:one_second, Time.now)
    assert Job.sink[:one_second].nil?
    sleep 0.1
    assert Job.sink[:one_second].nil?
    wait_for(Job.sink[:one_second].nil?, 2.5)
    assert Job.sink[:one_second]
  end

  def wait_for(condition, time)
    slept = 0
    step = 0.01
    while slept < time && condition
      sleep step
      slept += step
    end
  end

end


