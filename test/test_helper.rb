# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
end

require "litestack"

require "minitest/autorun"

$litejobqueue = Litejobqueue.jobqueue(path: ":memory:", retries: 1, retry_delay: 1, retry_delay_multiplier: 1, queues: [["test", 1]], logger: nil)

# Setup a class to allow us to track and test whether code has been performed
class Performance
  def self.reset!
    @performances = 0
  end

  def self.performed!
    @performances ||= 0
    @performances += 1
  end

  def self.processed!(item, scope: :default)
    @processed_items ||= {}
    @processed_items[scope] ||= []
    @processed_items[scope] << item
  end

  def self.processed_items(scope = :default)
    @processed_items[scope]
  end

  def self.performances
    @performances || 0
  end
end

def perform_enqueued_jobs(&block)
  yield # enqueue jobs

  # iterate over enqueued jobs and perform them
  until $litejobqueue.count.zero?
    id, serialized_job = $litejobqueue.pop
    next if id.nil?
    $litejobqueue.send(:process_job, "default", id, serialized_job, false)
  end
end

def perform_enqueued_job
  performed = false
  attempts = 0

  # get first enqueued jobs and perform it
  until performed
    attempts += 1
    id, serialized_job = $litejobqueue.pop
    next if id.nil?
    $litejobqueue.send(:process_job, "default", id, serialized_job, false)
    performed = true
  end
end
