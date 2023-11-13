require_relative "../litestack/litemetric"
require_relative "./job/poppable"
require_relative "./job/enqueueable"
require_relative "./job/countable"
require_relative "./job/runnable"

module LiteJob
  class Job
    include ::Litemetric::Measurable, Poppable, Enqueueable, Countable, Runnable

    def self.destroy(id)
      destroy_statement = DatabaseConnection.get_or_create_cached_statement(:destroy, "DELETE FROM queue WHERE id = ?;")
      destroy_statement.execute!(id)
    end

    attr_reader :id, :class_name, :params, :delay, :queue, :retries, :fire_at

    def initialize(params = {})
      @id = params[:id]
      @class_name = params[:class_name]
      @params = params[:params]
      @delay = params[:delay]
      @queue = params[:queue]
      @retries = params[:retries] || LiteJob.configuration.retries
      @fire_at = params[:fire_at]
      @considered_dead_after = params[:considered_dead_after] || LiteJob.configuration.considered_dead_after

      if params[:serialized_value]
        parsed_value = Oj.load(params[:serialized_value])
        @params = parsed_value["params"]
        @class_name = parsed_value["klass"]
        @retries = parsed_value["retries"]
        @original_queue = parsed_value["original_queue"]
        @considered_dead_after = parsed_value["considered_dead_after"] || LiteJob.configuration.considered_dead_after
      end

      @original_queue ||= @queue
    end

    def reload
      reload_statement = DatabaseConnection.get_or_create_cached_statement :reload, <<~SQL
        SELECT id, name, fire_at, value, created_at 
        FROM queue 
        WHERE id = ?;
      SQL

      row = reload_statement.execute!(@id)[0]
      @id, @queue, @fire_at, serialized_value, @created_at = row
      parsed_value = Oj.load(serialized_value)
      @params = parsed_value["params"]
      @class_name = parsed_value["klass"]
      @retries = parsed_value["retries"]
      @original_queue = parsed_value["original_queue"]
      self
    end

    def destroy
      destroy_statement = DatabaseConnection.get_or_create_cached_statement(:destroy, "DELETE FROM queue WHERE id = ?;")
      destroy_statement.execute!(@id)
    end

    def logger
      LiteJob.logger
    end

    def serialize
      Oj.dump({
                klass: @class_name,
                params: @params,
                retries: @retries,
                queue: @queue,
                original_queue: @original_queue,
                considered_dead_after: @considered_dead_after
              },
              mode: :strict)
    end
  end
end