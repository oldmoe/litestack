require 'minitest/autorun'
require '../lib/litestack/litejob.rb'

class MyJob

  @@attempts = {}
  
  def perform(time)
    #puts "performing"
    raise "An error occured" if Time.now.to_i < time
  end
end

class TestQueue < Minitest::Test
  def setup
    @jobqueue = Litejobqueue.new({path: ":memory:", retries: 2, retry_delay: 1, retry_delay_multiplier: 1, queues: [['test', 1]]})
    @jobqueue.clear
  end

  def test_push
    @jobqueue.push(MyJob.name, [Time.now.to_i], 0, 'test')
    assert @jobqueue.count != 0
    sleep 0.3
    assert @jobqueue.count == 0    
  end

  def test_delete
    assert @jobqueue.count == 0
    id = @jobqueue.push(MyJob.name, [Time.now.to_i], 10, 'test')
    assert @jobqueue.count != 0
    @jobqueue.count 
    @jobqueue.delete(id, 'test')
    assert @jobqueue.count == 0    
  end  

  def test_push_with_delay
    assert @jobqueue.count == 0
    id = @jobqueue.push(MyJob.name, [Time.now.to_i], 2, 'test')
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 2.5
    assert @jobqueue.count == 0    
  end
  
  def test_retry
    # should fail twice
    id = @jobqueue.push(MyJob.name, [Time.now.to_i+2], 0, 'test')
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 2.5
    assert @jobqueue.count == 0
    # should fail forever
    id = @jobqueue.push(MyJob.name, [Time.now.to_i+3], 0, 'test')
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    sleep 3.5
    assert @jobqueue.count != 0
    @jobqueue.clear    
  end

end

