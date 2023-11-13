module LiteJob
  class Job
    module Enqueueable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def enqueue(klass, params, delay, queue = "default")
          class_name = klass.name
          considered_dead_after = klass.respond_to?(:lite_job_considered_dead_after) ?
                                      klass.lite_job_considered_dead_after :
                                      LiteJob.configuration.considered_dead_after
          job = new(class_name: class_name,
                    params: params,
                    delay: delay,
                    queue: queue,
                    considered_dead_after: considered_dead_after)
          job.enqueue
          job
        end
      end

      def enqueue
        enqueue_statement = DatabaseConnection.get_or_create_cached_statement :enqueue, <<~SQL
          INSERT INTO queue(id, name, fire_at, value)
          VALUES (hex(randomblob(32)), ?, ?, ?)
          RETURNING id, name;
        SQL

        @fire_at = Time.now.utc.to_i + @delay
        id, queue_name = enqueue_statement.execute!(@queue, @fire_at, serialize)[0]
        capture(:enqueue, @queue)
        @id = id
        logger.info("[litejob]:[ENQ] queue:#{queue_name} class:#{@class_name} job:#{id}")
      end

      def requeue(exception)
        requeue_statement = DatabaseConnection.get_or_create_cached_statement :requeue, <<~SQL
          UPDATE queue
          SET 
            name = ?,
            fire_at = ?,
            value = ?
          WHERE 
              id = ?;
        SQL

        retry_delay = if @retries == 0
                        LiteJob.configuration.dead_job_retention
                      else
                        LiteJob.configuration.retry_delay_multiplier.pow(LiteJob.configuration.retries - @retries) * LiteJob.configuration.retry_delay
                      end
        @fire_at = Time.now.utc.to_i + retry_delay
        @queue = @retries == 0 ? "_dead" : @original_queue
        @retries -= 1 unless @retries == 0

        requeue_statement.execute!(@queue, @fire_at, serialize, @id)[0]
        capture(:enqueue, @queue)

        if @retries == 0
          capture(:fail, @queue)
          logger.error "[litejob]:[ERR] queue:#{@queue} class:#{@class_name} job:#{@id} failed with #{exception}:#{exception.message}, retries exhausted, moved to _dead queue"
        else
          capture(:retry, @queue)
          logger.error "[litejob]:[ERR] queue:#{@queue} class:#{@class_name} job:#{@id} failed with #{exception}:#{exception.message}, retrying in #{retry_delay} seconds"
        end
      end
    end
  end
end