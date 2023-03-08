require 'minitest/autorun'
require '../lib/litestack/litejob.rb'

jobqueue = Litejobqueue.new({path: ":memory:", retries: 2, retry_delay: 1, retry_delay_multiplier: 1, queues: [['test', 1]]})

class MyJob

  include ::Litejob

  self.queue = 'test'

  @@attempts = {}
  
  def perform(time)
    #puts "performing"
    raise "An error occured" if Time.now.to_i < time
  end
end

class TestQueue < Minitest::Test
  def setup
    @jobqueue = Litejobqueue.new({path: ":memory:", retries: 2, retry_delay: 1, retry_delay_factor: 1, queues: [['test', 1]]})
    @jobqueue.clear
  end

  def test_job_execute
    MyJob.perform_async(Time.now.to_i)
    assert @jobqueue.count != 0
    sleep 0.3
    assert @jobqueue.count == 0    
  end

  def test_job_delete
    assert @jobqueue.count == 0
    id = MyJob.perform_in(10, Time.now.to_i)
    assert @jobqueue.count != 0
    @jobqueue.count 
    MyJob.delete(id)
    assert @jobqueue.count == 0    
  end  

  def test_job_perform_at
    assert @jobqueue.count == 0
    MyJob.perform_at(Time.now.to_i + 2, Time.now.to_i)
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 2.5
    assert @jobqueue.count == 0    
  end
  
  def test_job_perform_in
    assert @jobqueue.count == 0
    MyJob.perform_in(2, Time.now.to_i)
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 2.5
    assert @jobqueue.count == 0    
  end    

  def test_job_retry
    # should fail twice
    MyJob.perform_async(Time.now.to_i + 2)    
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 2.5
    assert @jobqueue.count == 0
    # should fail forever
    MyJob.perform_async(Time.now.to_i + 3)    
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 3.5
    assert @jobqueue.count != 0
    @jobqueue.clear    
  end

end

