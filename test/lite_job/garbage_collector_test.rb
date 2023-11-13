require_relative "../test_helper"
require "lite_job"
require "minitest/autorun"
require_relative "test_jobs"

class GarbageCollectorTest < LiteTestCase
  def test_worker_processes_jobs_from_configured_queues
    LiteJob.enqueue(TestJob, {}, 0, "default")
    LiteJob.instance_variable_set(:@running, true)
    LiteJob::GarbageCollector.run
    assert_equal 1, LiteJob.count

    LiteJob.enqueue(TestJob, {}, 0, "_dead")

    sleeps = 0
    while(LiteJob.count > 1 && sleeps < 10)
      sleep 0.001
      sleeps += 1
    end

    jobs = LiteJob::Job.all
    assert_equal 1, jobs.count
    assert_equal "default", jobs.first.queue
  end
end