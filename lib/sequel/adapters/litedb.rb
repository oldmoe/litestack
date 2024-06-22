require_relative "../../litestack/litedb"
require "sequel"
require "sequel/adapters/sqlite"

module Sequel
  module Litedb
    include SQLite

    LITEDB_TYPES = SQLITE_TYPES

    class Database < Sequel::SQLite::Database
      set_adapter_scheme :litedb

      def connect(server)
        Sequel.extension :fiber_concurrency if [:fiber, :polyphony].include? Litescheduler.backend

        opts = server_opts(server)
        opts[:database] = ":memory:" if blank_object?(opts[:database])
        sqlite3_opts = {}
        sqlite3_opts[:readonly] = typecast_value_boolean(opts[:readonly]) if opts.has_key?(:readonly)
        db = ::Litedb.new(opts[:database].to_s, sqlite3_opts)
        @raw_db = db

        self.transaction_mode = :immediate

        if sqlite_version >= 104
          db.extended_result_codes = true
        end

        connection_pragmas.each { |s| log_connection_yield(s, db) { db.execute_batch(s) } }

        class << db
          attr_reader :prepared_statements
        end

        db.instance_variable_set(:@prepared_statements, {})
        db
      end

      def sqlite_version
        @raw_db.sqlite_version
      end
    end

    class Dataset < Sequel::SQLite::Dataset
      def supports_insert_select?
        true
      end
    end
  end
end
