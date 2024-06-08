require "minitest/autorun"
require_relative "../lib/litestack/litequeue"

class TestQueue < Minitest::Test
  def setup
    @queue = Litequeue.new({path: ":memory:"})
    @queue.clear
  end

  def test_clear
    10.times do
      @queue.push(1)
    end
    assert @queue.count != 0
    @queue.clear
    assert @queue.count == 0
  end

  def test_depletion
    assert @queue.count == 0
    10.times do
      @queue.push(1)
    end
    assert @queue.count == 10
    10.times do
      @queue.pop
    end
    assert @queue.count == 0
  end

  def test_queues
    @queue.push(1, 0, "def")
    assert @queue.pop.nil?
    assert !@queue.pop("def").nil?
  end

  def test_delay
    @queue.push(1, 1)
    assert @queue.pop.nil?
    sleep 1
    assert !@queue.pop.nil?
  end

  def test_find
    j1 = @queue.push(1, 0, "q1")
    j2 = @queue.push(2, 10, "q2")
    res = @queue.find({fire_at: [Time.now.to_i + 1, nil]})
    assert_equal 1, res.length
    assert_equal j2[0], res[0][0]
    res = @queue.find
    assert_equal 2, res.length
    res = @queue.find(created_at: [Time.now.to_i, nil])
    assert_equal 2, res.length
    res = @queue.find({fire_at: [nil, Time.now.to_i + 1]})
    assert_equal 1, res.length
    assert_equal j1[0], res[0][0]
    res = @queue.find({fire_at: [Time.now.to_i + 1, Time.now.to_i + 11]})
    assert_equal 1, res.length
    assert_equal j2[0], res[0][0]
    res = @queue.find({fire_at: [Time.now.to_i + 1, Time.now.to_i + 2]})
    assert_equal 0, res.length
  end
end
