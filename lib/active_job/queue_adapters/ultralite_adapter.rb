# frozen_string_literal: true

require "ultralite"
require_relative '../../ultralite/job.rb'
require "active_support/core_ext/enumerable"
require "active_support/core_ext/array/access"
require "active_job"

module ActiveJob
  module QueueAdapters
    # == Ultralite adapter for Active Job
    #
    #
    #   Rails.application.config.active_job.queue_adapter = :ultralite
    class UltraliteAdapter
      
      DEFAULT_CONFIG_PATH = "./config/ultrajob.yaml"

      def initialize(options={})
        options[:config_path] = DEFAULT_CONFIG_PATH unless options[:config_path]
        @options = options 
        Job.options = @options
      end
    
      def enqueue(job) # :nodoc:
        Job.queue = job.queue_name
        Job.perform_async(job.serialize)
      end

      def enqueue_at(job, timestamp) # :nodoc:
        Job.queue = job.queue_name
        Job.perform_at(timestamp, job.serialize)
      end

      class Job # :nodoc:
        
        include ::Ultralite::Job
  
        def perform(job_data)
          Base.execute job_data
        end
      end
    end
  end
end
