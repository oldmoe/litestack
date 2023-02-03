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
    
      def enqueue(job) # :nodoc:
        #job.provider_job_id = 
        Job.perform_async(job.serialize, 0, job.queue_name)
      end

      def enqueue_at(job, timestamp) # :nodoc:
        Job.perform_async(job.serialize, timestamp, job.queue_name)
      end

      class Job # :nodoc:
        include ::Ultralite::Job
        #class << self
          def perform(job_data)
            Base.execute job_data
          end
        #end
      end
    end
  end
end


ActiveJob::Base.queue_adapter = :ultralite
$count = 10000
class GuestsCleanupJob < ActiveJob::Base
  queue_as :default
 
  def perform(msg, index, t)
    puts "performed #{index} #{msg} ops in #{Time.now.to_f - t} seconds" if index == $count
  end
end
t = Time.now.to_f
$count.times do |i|
  GuestsCleanupJob.perform_later("clean", i+1, t)
end
sleep
