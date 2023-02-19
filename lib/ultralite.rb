# frozen_string_literal: true

# load core classes
require_relative "ultralite/version"
require_relative "ultralite/env"
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


