require 'ultralite'
require 'msgpack'
require 'oj'
require_relative './queue'

# the job queue relies on the queue to:
# 1 - enqueue jobs
# 2 - run them
module Ultralite
  class JobQueue
    def initialize(options = {})
      @queue = ::Ultralite::Queue.new # create new queue object
      @worker_count = options[:workers] ||= 1
      @workers = []
      # insure these are only created once per queue
      @worker_count.times do
        create_worker_thread
      end
    end

    def push(jobclass, params, delay=0, queue=nil)
      payload = Oj.dump([jobclass, params])
      @queue.push(payload, delay, queue)
    end
        
    def delete(id)
      job = @queue.delete(id)
      MessagePack.unpack(job) if job
    end
    
    def create_worker_thread
      # constantly check the queue for jobs (all queues?)
      @workers << Thread.new do
        queue = ::Ultralite::Queue.new # create new queue object
        loop do
          while payload = queue.pop
            id, job = payload[0], payload[1]
            job = Oj.load(job)
            klass = eval(job[0])
            begin
              klass.new.perform(job[1])
            rescue Exception => e
              puts e
              puts e.message
              puts e.backtrace
            end
          end
          sleep 2
        end
      end
      
      @workers.last.priority = -100 
    end
    
    
  end
end
