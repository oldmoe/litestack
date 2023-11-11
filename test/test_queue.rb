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
      @queue.pop("test worker")
    end
    assert @queue.pop("test worker").nil?
  end

  def test_queues
    @queue.push(1, 0, "def")
    assert @queue.pop("test worker").nil?
    assert !@queue.pop("test worker", "def").nil?
  end

  def test_delay
    @queue.push(1, 1)
    assert @queue.pop("test worker").nil?
    sleep 1
    assert !@queue.pop("test worker").nil?
  end

  def test_jobs_assigned_to_workers_can_not_be_popped_twice
    @queue.push(1, 0)
    refute @queue.pop("test worker").nil?
    assert @queue.pop("test worker 2").nil?
  end

  def test_jobs_assigned_to_dead_workers_are_requeued
    @queue.push(1, 0)
    refute @queue.pop("test worker").nil?
    @queue.rescue_abandoned_jobs
    refute @queue.pop("test worker").nil?
  end

  def test_jobs_assigned_to_live_workers_are_not_requeued
    @queue.push(1, 0)
    @queue.register_worker("test worker")
    @queue.pop("test worker")
    @queue.rescue_abandoned_jobs
    assert @queue.pop("test worker").nil?
  end

  def test_dead_workers_are_cleaned_up
    @queue.register_worker("test worker")
    @queue.clear_dead_workers(Time.now.to_i + 1)
    assert @queue.workers.empty?
  end

  def test_live_workers_are_not_cleaned_up
    @queue.register_worker("test worker")
    @queue.clear_dead_workers(Time.now.to_i - 1)
    refute @queue.workers.empty?
  end
end
