require_relative "../litestack/litemetric"

module LiteJob
  class Worker
    include Litemetric::Measurable

    def initialize
      @sleep_index = 0
      collect_metrics if LiteJob.configuration.metrics
    end

    def run
      return if @running
      @running = true

      @worker_thread = Litescheduler.spawn do
        while LiteJob.running? && @running
          processed = 0
          queues.each do |priority, queues|
            # iterate through the levels
            queues.each do |queue, should_spawn|
              # iterate through the queues in the level
              batched = 0

              while (batched < priority) && (job = LiteJob.pop(queue))
                capture(:dequeue, queue)
                processed += 1
                batched += 1

                job.run(should_spawn)

                Litescheduler.switch
              end
            end
          end

          if processed == 0
            sleep_intervals = LiteJob.configuration.sleep_intervals
            sleep sleep_intervals[@sleep_index]
            @sleep_index += 1 if @sleep_index < sleep_intervals.length - 1
          else
            @sleep_index = 0 # reset the index
          end
        end
      end
    end

    def running?
      @running
    end

    def kill
      Litescheduler.stop(@worker_thread)
      @running = false
    end

    private

    def queues
      return @queues if @queues

      @queues = LiteJob.configuration.queues.reduce({}) do |priority_groups, q|
        priority_groups[q[1]] ||= []
        priority_groups[q[1]] << [q[0], q[2] == "spawn"]
        priority_groups
      end.sort_by { |priority, _| -priority }.to_h
    end
  end
end