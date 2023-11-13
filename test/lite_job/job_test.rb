require_relative "../test_helper"
require "lite_job"
require "minitest/autorun"
require_relative "test_jobs"

class JobTest < LiteTestCase
  def test_queueing_a_job
    enqueue_jobs(2)
    assert_equal 2, LiteJob::Job.count
  end

  def test_popping_a_job
    enqueue_jobs(2, with_delay: -1)
    enqueue_jobs(with_delay: 10)

    refute_nil LiteJob::Job.pop
    assert_equal 2, LiteJob::Job.unassigned_count

    refute_nil LiteJob::Job.pop
    assert_equal 1, LiteJob::Job.unassigned_count

    Timecop.travel(Time.now.utc + 5) do
      assert_nil LiteJob::Job.pop
      assert_equal 1, LiteJob::Job.unassigned_count, "Jobs should not be popped before their fire_at time"
    end

    Timecop.travel(Time.now.utc + 10) do
      refute_nil LiteJob::Job.pop
      assert_equal 0, LiteJob::Job.unassigned_count
    end
  end

  def test_count
    enqueue_jobs(2)
    assert_equal 2, LiteJob::Job.count
  end

  def test_unassigned_count
    enqueue_jobs(2)
    refute_nil LiteJob::Job.pop
    assert_equal 1, LiteJob::Job.unassigned_count
  end

  def test_running_a_job
    LiteJob::Job.enqueue(TestJob, nil, 0)
    job = LiteJob::Job.pop
    refute_nil job
    job.run
    assert_equal 1, Performance.performances
  end

  def test_that_failed_jobs_are_requeued_in_their_original_queue
    LiteJob::Job.enqueue(FailingJob, nil, -1)
    job = LiteJob::Job.pop
    refute_nil job
    job.run
    assert_equal 1, LiteJob::Job.unassigned_count
  end

  def test_successful_jobs_are_removed
    LiteJob::Job.enqueue(TestJob, nil, -1)
    job = LiteJob::Job.pop
    refute_nil job
    job.run
    assert_equal 0, LiteJob::Job.count
  end

  def test_that_requeued_jobs_are_reprocessed
    LiteJob.configuration.retries = 2
    LiteJob.configuration.retry_delay = 5
    LiteJob.configuration.retry_delay_multiplier = 1

    LiteJob::Job.enqueue(FailingJob, nil, -1)

    job = LiteJob::Job.pop
    refute_nil job
    job.run
    assert_equal 0, LiteJob::Job.dead_count

    Timecop.travel(Time.now.utc + LiteJob.configuration.jobs_assumed_dead_after) do
      job = LiteJob::Job.pop
      job.run
    end
    assert_equal 0, LiteJob::Job.dead_count

    Timecop.travel(Time.now.utc + 14) do
      assert_nil LiteJob::Job.pop, "Job should not be popped before its fire_at time"
    end

    Timecop.travel(Time.now.utc + 10_000) do
      job = LiteJob::Job.pop
      job.run
    end
    assert_equal 1, LiteJob::Job.dead_count
  end

  def test_jobs_with_multiple_parameters
    LiteJob::Job.enqueue(TestMultipleParameterJob, [1, 2], -1)
    job = LiteJob::Job.pop
    refute_nil job
    job.run
    assert_equal 1, Performance.performances
    assert_equal [1, 2], Performance.processed_items.first
  end

  def test_dead_jobs_are_repopped
    LiteJob::Job.enqueue(TestJob, nil, 0)
    LiteJob::Job.pop
    Timecop.travel(Time.now.utc + LiteJob.configuration.jobs_assumed_dead_after - 2) do
      assert_nil LiteJob::Job.pop
    end

    Timecop.travel(Time.now.utc + LiteJob.configuration.jobs_assumed_dead_after + 1) do
      refute_nil LiteJob::Job.pop
    end
  end

  def test_jobs_can_specify_their_own_dead_after
    TestJob.considered_dead_after 60 * 45
    j = LiteJob::Job.enqueue(TestJob, nil, 0)
    TestJob.considered_dead_after nil
    assert_in_delta Time.now.utc.to_i, j.reload.fire_at, 1
    LiteJob::Job.pop
    assert_in_delta Time.now.utc.to_i + (60 * 45), j.reload.fire_at, 1
  end

  private

  def enqueue_jobs(times = 1, with_delay: 0)
    times.times do
      LiteJob::Job.enqueue(TestJob, [1, 2], with_delay)
    end
  end
end