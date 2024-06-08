# frozen_string_literal: true

require_relative "../../litestack/litejob"
require "active_support"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/array/access"
require "active_job"

module ActiveJob
  module QueueAdapters
    # == Litestack adapter for Active Job
    #
    #
    #   Rails.application.config.active_job.queue_adapter = :litejob
    class LitejobAdapter
      def initialize(options = {})
        # we currently don't honour individual options per job class
        # possible in the future?
        # Job.options = DEFAULT_OPTIONS.merge(options)
      end

      def enqueue_after_transaction_commit?
        Job.options[:enqueue_after_transaction_commit]
      end

      def enqueue(job) # :nodoc:
        Job.queue = job.queue_name
        Job.perform_async(job.serialize)
      end

      def enqueue_at(job, time) # :nodoc:
        time = time.from_now if time.respond_to?(:from_now) # is_a?(ActiveSupport::Duration)
        Job.queue = job.queue_name
        Job.perform_at(time, job.serialize)
      end

      class Job # :nodoc:
        DEFAULT_OPTIONS = {
          config_path: "./config/litejob.yml",
          logger: nil, # Rails performs its logging already
          enqueue_after_transaction_commit: true
        }

        include ::Litejob

        def perform(job_data)
          Base.execute job_data
        end
      end
    end
  end
end
