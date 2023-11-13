module LiteJob
  class Job
    module Runnable
      def run(should_spawn = false)
        conditionally_spawn(should_spawn) do
          @running = true
          logger.info "[litejob]:[DEQ] queue:#{@queue} class:#{@class_name} job:#{@id}"
          klass = Object.const_get(@class_name)
          LiteJob.job_started
          begin
            measure(:perform, @queue) { klass.new.perform(*@params) }
            destroy
            logger.info "[litejob]:[END] queue:#{@queue} class:#{@class_name} job:#{@id}"
          rescue Exception => e # standard:disable Lint/RescueException
            capture(:fail, @queue)
            requeue(e)
          end
          LiteJob.job_finished
        rescue Exception => e # standard:disable Lint/RescueException
          # this is an error in the extraction of job info, retrying here will not be useful
          logger.error "[litejob]:[ERR] failed to extract job info for: #{@params} with #{e}:#{e.message}"
          LiteJob.job_finished
        ensure
          @running = false
        end
      end

      private

      def conditionally_spawn(should_spawn = false, &block)
        if should_spawn
          Litescheduler.spawn(&block)
        else
          yield
        end
      end
    end
  end
end