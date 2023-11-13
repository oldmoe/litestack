require "singleton"

module LiteJob
  module GarbageCollector
    def self.run
      return if @running

      @running = true
      @garbage_collector_thread = Litescheduler.spawn do
        while LiteJob.running? && @running
          while (jobs = clear_dead_jobs(100))
            if jobs[0].is_a? Array
              logger.info "[litejob]:[DEL] garbage collector deleted #{jobs.length} dead jobs"
            else
              logger.info "[litejob]:[DEL] garbage collector deleted 1 dead job"
            end
          end
          sleep LiteJob.configuration.gc_sleep_interval
        end
      end
    end

    def self.clear_dead_jobs(limit)
      clear_dead_jobs_statement = DatabaseConnection.get_or_create_cached_statement :clear_dead_jobs, <<~SQL
        DELETE FROM queue
        WHERE id IN (
          SELECT id from queue
          WHERE name = '_dead' AND fire_at <= ?
          LIMIT ifnull(?, 1)
        )
        RETURNING id;
      SQL

      res = clear_dead_jobs_statement.execute!(Time.now.utc.to_i, limit)
      return res[0] if res.length == 1
      return nil if res.empty?
      res
    end

    def running?
      @running
    end

    def self.kill
      Litescheduler.stop(@garbage_collector_thread) if @garbage_collector_thread
      @running = false
    end

    def self.logger
      LiteJob.logger
    end
  end
end