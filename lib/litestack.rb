# frozen_string_literal: true

# load core classes
#require_relative "./version"
require_relative "litestack/litesupport"
#require_relative "litedb"
require_relative "litestack/litecache"
require_relative "litestack/litejob"

# conditionally load integration with other libraries
#require_relative "../sequel/adapters/litedb" if defined? Sequel
#require_relative "../active_record/connection_adapters/litedb_adapter" if defined? ActiveRecord
require_relative "active_support/cache/litecache" if defined? ActiveSupport
require_relative "active_job/queue_adapters/litejob_adapter" if defined? ActiveJob
#require_relative "../railties/rails/commands/dbconsole" if defined? Rails
