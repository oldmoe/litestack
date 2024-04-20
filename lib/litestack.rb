# frozen_string_literal: true

# load core classes
require_relative "litestack/version"
require_relative "litestack/litescheduler"
require_relative "litestack/litesupport"
require_relative "litestack/litemetric"
require_relative "litestack/litedb"
require_relative "litestack/litecache"
require_relative "litestack/litejob"
require_relative "litestack/litecable"

# conditionally load integration with other libraries
require_relative "sequel/adapters/litedb" if defined? Sequel
require_relative "active_record/connection_adapters/litedb_adapter" if defined? ActiveRecord
require_relative "railties/rails/commands/dbconsole" if defined?(Rails) && defined?(ActiveRecord)
require_relative "active_support/cache/litecache" if defined? ActiveSupport
require_relative "active_job/queue_adapters/litejob_adapter" if defined? ActiveJob
require_relative "action_cable/subscription_adapter/litecable" if defined? ActionCable
require_relative "litestack/railtie" if defined? Rails::Railtie

module Litestack
  class NotImplementedError < RuntimeError; end

  class TimeoutError < RuntimeError; end

  class DeadlockError < RuntimeError; end
end
