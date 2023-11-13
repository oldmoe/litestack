require_relative "../test_helper"
require "lite_job"
require "minitest/autorun"
require_relative "test_jobs"

class WorkerTest < LiteTestCase
  def test_worker_processes_jobs_from_configured_queues
    LiteJob.configuration.queues = [["default", 1], ["high", 2]]
    LiteJob.enqueue(TestJob, {}, 0, "default")
    LiteJob.enqueue(TestJob, {}, 0, "high")
    LiteJob.enqueue(TestJob, {}, 0, "not_registered")

    LiteJob.instance_variable_set(:@running, true)
    worker = LiteJob::Worker.new.tap { |w| w.run }
    sleeps = 0
    while LiteJob.count > 1 && sleeps < 10
      sleep 0.001
      sleeps += 1
    end
    worker.kill

    jobs = LiteJob::Job.all
    assert_equal 1, jobs.length
    assert_equal "not_registered", jobs.first.queue
  end

  def test_kill_worker_stops_job_processing
    LiteJob.enqueue(TestJob, {}, 0, "default")
    LiteJob.instance_variable_set(:@running, true)
    worker = LiteJob::Worker.new.tap { |w| w.run }

    sleeps = 0
    while LiteJob.count != 0 && sleeps < 10
      sleep 0.001
      sleeps += 1
    end
    worker.kill
    assert_equal 0, LiteJob.count
    refute worker.running?

    LiteJob.enqueue(TestJob, {}, 0, "default")
    sleep 0.1
    assert_equal 1, LiteJob.count
  end
end