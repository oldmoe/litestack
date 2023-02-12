# frozen_string_literal: true

require 'sqlite3'

# load core classes
require_relative "ultralite/version"
require_relative "ultralite/db"
require_relative "ultralite/cache"
require_relative "ultralite/queue"
require_relative "ultralite/job_queue"
require_relative "ultralite/job"

# conditionally load integration with other libraries
require_relative "sequel/adapters/ultralite" if defined? Sequel
require_relative "active_record/connection_adapters/ultralite_adapter" if defined? ActiveRecord
require_relative "active_support/cache/ultralite_cache_store" if defined? ActiveSupport
require_relative "active_job/queue_adapters/ultralite_adapter" if defined? ActiveJob
require_relative "railties/rails/commands/dbconsole" if defined? Rails

module Ultralite
  class Error < StandardError; end
  
  def self.environment
    @env ||= detect_environment
  end
  
  def self.detect_environment
    return :fiber_scheduler if Fiber.scheduler 
    return :polyphony if defined? Polyphony
    return :iodine if defined? Iodine
    return :threaded 
  end
end
