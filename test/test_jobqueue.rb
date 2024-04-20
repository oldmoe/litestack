require "minitest/autorun"
require_relative "../lib/litestack/litejobqueue"

class Litejobqueue
  def at_exit
    # do nothing
  end
end

class MyJob
  @@attempts = {}

  def perform(time)
    # puts "performing"
    raise "An error occurred" if Time.now.to_i < time
  end
end

class TestJobQueue < Minitest::Test
  def setup
    @jobqueue = Litejobqueue.new({path: ":memory:", logger: nil, retries: 2, retry_delay: 1, retry_delay_multiplier: 1, queues: [["test", 1]]})
  end

  def teardown
    @jobqueue.clear
  end

  def test_push
    @jobqueue.push(MyJob.name, [Time.now.to_i], 0, "test")
    assert @jobqueue.count != 0
    assert 0..2, @jobqueue.count == 0
    @jobqueue.clear
  end

  def test_delete
    assert @jobqueue.count == 0
    id = @jobqueue.push(MyJob.name, [Time.now.to_i], 10, "test")
    assert @jobqueue.count != 0
    @jobqueue.count
    @jobqueue.delete(id[0])
    assert @jobqueue.count == 0
  end

  def test_push_with_delay
    assert @jobqueue.count == 0
    @jobqueue.push(MyJob.name, [Time.now.to_i], 1, "test")
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    assert 0..2, @jobqueue.count == 0
    @jobqueue.clear
  end

  def test_retry
    # should fail twice
    @jobqueue.push(MyJob.name, [Time.now.to_i + 2], 0, "test")
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    assert 0..3, @jobqueue.count("test") == 0
    # should fail forever
    @jobqueue.push(MyJob.name, [Time.now.to_i + 3], 0, "test")
    assert @jobqueue.count != 0
    sleep 0.1
    assert @jobqueue.count != 0
    assert 0..3, @jobqueue.count("test") == 0
    @jobqueue.clear
  end
end
