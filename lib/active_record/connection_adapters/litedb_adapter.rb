require_relative "../../litestack/litedb"

require "active_record"
require "active_record/connection_adapters/sqlite3_adapter"
require "active_record/tasks/sqlite_database_tasks"

module ActiveRecord
  module ConnectionHandling # :nodoc:
    def litedb_connection(config)
      config = config.symbolize_keys

      # Require database.
      unless config[:database]
        raise ArgumentError, "No database file specified. Missing argument: database"
      end

      # Allow database path relative to Rails.root, but only if the database
      # path is not the special path that tells sqlite to build a database only
      # in memory.
      if config[:database] != ":memory:" && !config[:database].to_s.start_with?("file:")
        config[:database] = File.expand_path(config[:database], Rails.root) if defined?(Rails.root)
        dirname = File.dirname(config[:database])
        Dir.mkdir(dirname) unless File.directory?(dirname)
      end

      db = ::Litedb.new(
        config[:database].to_s,
        config.merge(results_as_hash: true)
      )

      ConnectionAdapters::LitedbAdapter.new(db, logger, nil, config)
    rescue Errno::ENOENT => error
      if error.message.include?("No such file or directory")
        raise ActiveRecord::NoDatabaseError
      else
        raise
      end
    end
  end

  module ConnectionAdapters # :nodoc:
    class LitedbAdapter < SQLite3Adapter
      ADAPTER_NAME = "litedb"

      class << self
        def dbconsole(config, options = {})
          args = []

          args << "-#{options[:mode]}" if options[:mode]
          args << "-header" if options[:header]
          args << File.expand_path(config.database, Rails.respond_to?(:root) ? Rails.root : nil)

          find_cmd_and_exec("sqlite3", *args)
        end
      end

      NATIVE_DATABASE_TYPES = {
        primary_key: "integer PRIMARY KEY NOT NULL",
        string: {name: "text"},
        text: {name: "text"},
        integer: {name: "integer"},
        float: {name: "real"},
        decimal: {name: "real"},
        datetime: {name: "text"},
        time: {name: "integer"},
        date: {name: "text"},
        binary: {name: "blob"},
        boolean: {name: "integer"},
        json: {name: "text"},
        unixtime: {name: "integer"}
      }

      private

      def connect
        @raw_connection = ::Litedb.new(
          @config[:database].to_s,
          @config.merge(results_as_hash: true)
        )
        configure_connection
      end
    end
  end

  module Tasks # :nodoc:
    class LitedbDatabaseTasks < SQLiteDatabaseTasks # :nodoc:
    end

    module DatabaseTasks
      register_task(/litedb/, "ActiveRecord::Tasks::LitedbDatabaseTasks")
    end
  end
end

if ActiveRecord::ConnectionAdapters.respond_to?(:register)
  ActiveRecord::ConnectionAdapters.register(
    "litedb", "ActiveRecord::ConnectionAdapters::LitedbAdapter",
    "active_record/connection_adapters/litedb_adapter"
  )
end
