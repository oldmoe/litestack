module LiteJob
  module Runnable
    def run
      return if @running
      @running = true

      @workers = LiteJob.configuration.workers.times.collect { Worker.new.tap { |w| w.run } }
      LiteJob::GarbageCollector.run
    end

    def kill
      @running = false
      @workers.each(&:kill)
      LiteJob::GarbageCollector.kill
    end

    def job_started
      @jobs_in_flight += 1
    end

    def job_finished
      @jobs_in_flight -= 1
    end

    def running?
      @running
    end
  end
end