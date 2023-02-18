require 'ultralite'
require 'oj'
require 'yaml'
require_relative './queue'

# the job queue relies on the queue to:
# 1 - enqueue jobs
# 2 - run them
module Ultralite
  class JobQueue
  
    WORKER_SLEEP_INTERVAL = 1
    DEFAULT_CONFIG_PATH = "./ultrajob.yaml"
    #DEFAULT_CONFIG_PATH = ":memory:"
      
    def self.queue
      @@queue ||= self.new
    end
  
    def initialize(options = nil)
      @options = options
      config_path = @options[:config_path] ||= DEFAULT_CONFIG_PATH
      config = File.read(config_path) rescue nil
      @options.merge!(YAML.load(config)) if config
      @queue = ::Ultralite::Queue.new(@options) # create new queue object
      @worker_count = options[:workers] ||= 1
      @workers = []
      # insure these are only created once per queue
      queues = @options["queues"] ||= [['default', 1]]
      # group, order and sum queue priority
      queues.sort!{|a, b| a[1] <=> b[1]}
      pgroups = {}
      queues.each do |q| 
        pgroups[q[1]] = [] unless pgroups[q[1]]
        pgroups[q[1]] << q[0]
      end
      priorities = pgroups.keys.sort.reverse
      @queues = priorities.collect{|p| [p, pgroups[p]]}
      @worker_count.times do
        create_worker
      end
    end
    

    def push(jobclass, params, delay=0, queue=nil)
      payload = Oj.dump([jobclass, params])
      @queue.push(payload, delay, queue)
    end
        
    def delete(id)
      job = @queue.delete(id)
      Oj.load(job) if job
    end
    
    def switch
      if Ultralite.environment == :fiber_scheduler
        Fiber.scheduler.yield
      elsif Ultralite.environment == :polyphony
        Fiber.current.schedule
        Thread.current.switch_fiber
      end 
    end
    
    def create_worker
      #if Ultralite.environment == :fiber_scheduler
      #  create_fiber_scheduler_worker
      #elsif Ultralite.environment == :polyphony
      #  create_polyphony_worker
      #else
        create_threaded_worker
      #end           
    end

    def process_queues(queue)
      #sleep 0.25 # initial sleep to allow other components to ramp up 
      loop do
        processed = 0
        @queues.each do |level| # iterate through the levels
          level[1].each do |q| # iterate through the queues in the level
            index = 0
            max = level[0]
            while index < max and payload = queue.pop(q) #level[0].times do 
              processed += 1
              index += 1
              id, job = payload[0], payload[1]
              job = Oj.load(job)
              klass = eval(job[0])
              begin
                klass.new.perform(*job[1])
              rescue Exception => e
                puts e
                puts e.message
                puts e.backtrace
              end
              # give another contexts a chance to run here
              switch #if processed > 5
            end
          end
        end
        sleep WORKER_SLEEP_INTERVAL if processed == 0      
      end
    end
    
    def create_iodine_worker
      
    end
    
    def create_polyphony_worker
      spin do
        process_queues(@queue)
      end
    end
    
    def create_fiber_scheduler_worker
      Fiber.schedule do
        process_queues(@queue)
      end
    end
        
    def create_threaded_worker
      # constantly check the queue for jobs (all queues?)
      @workers << Thread.new do
        queue = ::Ultralite::Queue.new(@options) # create new queue object
        process_queues(queue)
      end
    end
    
    
  end
end
