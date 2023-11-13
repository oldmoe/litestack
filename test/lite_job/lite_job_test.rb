require_relative "../test_helper"
require "lite_job"
require "minitest/autorun"
require_relative "test_jobs"

class LiteJobTest < LiteTestCase
  def setup
    super

    LiteJob.configuration.queues = [["default", 1], ["high", 2]]
    LiteJob.configuration.sleep_intervals = [0.001]
    LiteJob.configuration.workers = 2
    LiteJob.configuration.gc_sleep_interval = 0.001
    LiteJob.configuration.dead_job_retention = 60 * 5
    LiteJob.configuration.retry_delay = 0.01
    LiteJob.configuration.retry_delay_multiplier = 0
    LiteJob.configuration.retries = 2
  end

  def teardown
    LiteJob.kill
    sleep 0.05 # Let all the workers finish
    super
  end

  def test_that_lite_job_processes_jobs
    LiteJob.enqueue(TestJob, {}, 5)
    assert_equal 1, LiteJob.count

    LiteJob.run

    Timecop.travel(Time.now.utc + 0.5) do
      # Give a worker time to pick up the job
      sleep 0.02
    end
    # Make sure jobs aren't picked up before their fires_at time
    assert_equal 1, LiteJob.count

    Timecop.travel(Time.now.utc + 6) do
      sleeps = 0
      while LiteJob.count != 0 && sleeps < 10
        sleep(0.01)
        sleeps += 1
      end
    end
    assert_equal 0, LiteJob.count
  end

  def test_that_lite_job_only_processes_jobs_for_configured_queues
    LiteJob.enqueue(TestJob, {}, 1)
    LiteJob.enqueue(TestJob, {}, 1, "high")
    LiteJob.enqueue(TestJob, {}, 1, "unregistered")
    assert_equal 3, LiteJob.count

    LiteJob.run

    Timecop.travel(Time.now.utc + 1) do
      sleeps = 0
      while LiteJob.count != 1 && sleeps < 10
        sleep(0.01)
        sleeps += 1
      end
    end
    jobs = LiteJob::Job.all
    assert_equal 1, jobs.count
    assert_equal "unregistered", jobs.first.queue
  end

  def test_that_lite_job_garbage_collects
    LiteJob.enqueue(FailingJob, {}, 0)
    LiteJob.run

    # Let the workers run and let the job die
    sleeps = 0
    while LiteJob.dead_count != 1 && sleeps < 100
      sleep(0.01)
      sleeps += 1
    end
    assert_equal 1, LiteJob.dead_count

    Timecop.travel(Time.now.utc + 300) do
      sleeps = 0
      while LiteJob.count != 0 && sleeps < 10
        sleep(0.01)
        sleeps += 1
      end
    end
    assert_equal 0, LiteJob.count
  end

  def test_running_many_jobs
    LiteJob.reset_configuration!

    1_000.times do
      LiteJob.enqueue(FibonacciJob, 10, 0)
    end
    assert_equal 1_000, LiteJob.count
    LiteJob.run

    sleeps = 0
    while LiteJob.count != 0 && sleeps < 10
      sleep(1)
      sleeps += 1
    end

    assert_equal 0, LiteJob.count
    assert_equal 1_000, Performance.performances
  end
end