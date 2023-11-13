require "litestack/litesupport"
require "litestack/litedb"
require "singleton"
require "forwardable"

module LiteJob
  class DatabaseConnection < Litedb
    include Singleton

    class << self
      extend Forwardable
      def_delegators :instance, :get_or_create_cached_statement, :execute, :transaction, :rollback
    end

    def initialize
      database_file = Litesupport.environment == "test" ? ":memory:" : Litesupport.root.join("queue.sqlite3")
      database_definition_file = File.join(__dir__, "litequeue.sql.yml")
      database_options = {
        database_definition_file: database_definition_file,
        metrics: LiteJob.configuration.metrics
      }
      super(database_file, database_options)
    end
  end
end