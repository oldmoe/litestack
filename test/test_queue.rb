require 'minitest/autorun'
require '../lib/litestack/litequeue.rb'

class TestQueue < Minitest::Test
  def setup
    @queue = Litequeue.new
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
    @queue.push(1, 0, 'def')
    assert @queue.pop == nil
    assert @queue.pop('def') != nil
  end
  
  def test_delay
    @queue.push(1, 1)
    assert @queue.pop == nil
    sleep 1
    assert @queue.pop != nil
  end  

end

