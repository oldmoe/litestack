# frozen_string_literal: true

require_relative "./test_helper"
require_relative "../lib/litestack/litejob"

class NoOpJob
  include Litejob

  def perform = nil
end

class LitejobTest < LiteTestCase
  def teardown
    NoOpJob.queue = nil
    super
  end

  def test_perform_async_pushes_job_to_the_queue
    job_id, queue = NoOpJob.perform_async

    assert job_id
    assert_equal "default", queue
    assert_equal 1, LiteJob.count("default")
  end

  def test_perform_at_queues_job
    _, queue = NoOpJob.perform_at(Time.now.to_i + 0.1)
    assert_equal "default", queue

    jobs = LiteJob::Job.all
    assert_equal 1, jobs.count
    assert_in_delta Time.now.to_i + 0.1, jobs.first.fire_at, 0.1
    assert_equal "default", jobs.first.queue
  end

  def test_perform_in_queues_job
    _, queue = NoOpJob.perform_in(300)
    assert_equal "default", queue

    jobs = LiteJob::Job.all
    assert_equal 1, jobs.count
    assert_in_delta Time.now.to_i + 300, jobs.first.fire_at, 0.1
    assert_equal "default", jobs.first.queue
  end

  def test_perform_after_queues_job
    _, queue = NoOpJob.perform_after(300)
    assert_equal "default", queue

    jobs = LiteJob::Job.all
    assert_equal 1, jobs.count
    assert_in_delta Time.now.to_i + 300, jobs.first.fire_at, 0.1
    assert_equal "default", jobs.first.queue
  end

  def test_delete_removes_the_job
    job = LiteJob::Job.enqueue(NoOpJob, [], 0)
    LiteJob::Job.destroy(job.id)
    assert_equal 0, LiteJob.count
  end

  def test_sets_queue_name
    NoOpJob.queue = "test"
    LiteJob.enqueue(NoOpJob, [], 0)
    assert_equal 1, LiteJob.count("test")
  end
end
