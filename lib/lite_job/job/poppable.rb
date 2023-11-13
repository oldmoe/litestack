module LiteJob
  class Job
    module Poppable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def pop(queue = "default")
          pop_statement = DatabaseConnection.get_or_create_cached_statement :pop, <<~SQL
            UPDATE queue 
            set fire_at = ? + COALESCE(json_extract(value, '$.considered_dead_after'), ?), name = 'processing'
            WHERE id IN (
              SELECT id FROM queue
              WHERE name IN (?, 'processing')
              AND fire_at <= ?
              ORDER BY fire_at ASC
              LIMIT 1
            )
            RETURNING id, value, name;
          SQL

          Litemetric.instance.capture(LiteJob.metrics_identifier, :dequeue, queue)
          id, payload, queue_name = pop_statement.execute!(
            Time.now.utc.to_i,
            LiteJob.configuration.jobs_assumed_dead_after,
            queue,
            Time.now.utc.to_i)[0]
          return nil if id.nil?

          new(id: id, queue: queue_name, serialized_value: payload)
        end
      end
    end
  end
end