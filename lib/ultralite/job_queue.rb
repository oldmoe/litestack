require 'oj'
require 'yaml'
require_relative './queue'

# the job queue relies on the queue to:
# 1 - enqueue jobs
# 2 - run them
module Ultralite
  class JobQueue
  
    DEFAULT_OPTIONS = {
      config_path: "./ultrajob.yml",
      path: "./queue.db",
      queues: [["default", 1, "spawn"]],
      workers: 1,
      sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 3.125]
    }
      
    def self.queue
      @@queue ||= self.new
    end
  
    # configuration options
    #
    # :workers (integer) : the number of workers to processe queues
    # :config_path (string) : the path to the configuration file
    # :path (string) : the path to the data file 
    #                  the special path ":memory:" will create an in memory queue, 
    #                  accessible from one process only
    # :queues (array) : sets the queues to be handled by the workers
    #                   ex: queues: [["default", 1], ["urgent", 5, "spawn"]] 
    #                   the first element is the name of the queue followed
    #                   by its priority, and then an optional "spawn" string
    #                   if spawn is present then in fiber based environments
    #                   this queue will spawn a new fiber per job 
    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      @worker_sleep_index = 0
      config = YAML.load_file(@options[:config_path]) rescue {} #an empty hash won't hurt
      config.each_key do |k| # symbolize keys
        config[k.to_sym] = config[k]
        config.delete k
      end
      @options.merge!(config)
      @queue = ::Ultralite::Queue.new(@options) # create new queue object
      # group and order queues according to their priority
      pgroups = {}
      @options[:queues].each do |q|
        pgroups[q[1]] = [] unless pgroups[q[1]]
        pgroups[q[1]] << [q[0], q[2] == "spawn"]
      end
      @queues = pgroups.keys.sort.reverse.collect{|p| [p, pgroups[p]]}
      @workers = @options[:workers].times.collect{create_worker} 
    end
    
    def push(jobclass, params, delay=0, queue=nil)
      payload = Oj.dump([jobclass, params])
      @queue.push(payload, delay, queue)
    end
        
    def delete(id)
      job = @queue.delete(id)
      Oj.load(job) if job
    end
    
    private

    # yield the fiber and return it to the ready queue
    def switch
      if Ultralite.environment == :fiber
        Fiber.scheduler.yield
      elsif Ultralite.environment == :polyphony
        Fiber.current.schedule
        Thread.current.switch_fiber
      end 
    end
    
    # optionally run a job in its own fiber
    def schedule(spawn = false, &block)
      if spawn
        if Ultralite.environment == :fiber
          Fiber.schedule &block
        elsif Ultralite.environment == :polyphony
          spin &block
        else
          yield
        end
      else
        yield
      end 
    end
    
    # create a worker according to environment
    def create_worker
      if Ultralite.environment == :fiber
        create_fiber_scheduler_worker
      elsif Ultralite.environment == :polyphony
        create_polyphony_worker
      else
        create_threaded_worker
      end           
    end

    def process_queues(queue)
      loop do
        processed = 0
        @queues.each do |level| # iterate through the levels
          level[1].each do |q| # iterate through the queues in the level
            index = 0
            max = level[0]
            while index < max && payload = queue.pop(q[0])  
              processed += 1
              index += 1
              begin
                id, job = payload[0], payload[1]
                job = Oj.load(job)
                klass = eval(job[0])
                schedule(q[1]) do # run the job in a new context
                  begin
                    klass.new.perform(*job[1])
                  rescue Exception => e
                    puts e
                    puts e.message
                    puts e.backtrace
                  end
                end
              rescue Exception => e
                puts e
                puts e.message
                puts e.backtrace
              end
              switch #give other context a chance to run here
            end
          end
        end
        if processed == 0 
          sleep @options[:sleep_intervals][@worker_sleep_index]      
          @worker_sleep_index += 1 if @worker_sleep_index < @options[:sleep_intervals].length - 1          
        else
          @worker_sleep_index = 0 # reset the index
        end
      end
    end
    
    def create_iodine_worker
      
    end
    
    def create_polyphony_worker
      spin do
        switch # give a breathing room to the main fiber so other workers can be spawned
        process_queues(@queue)
      end
    end
    
    def create_fiber_scheduler_worker
      Fiber.schedule do
        switch # give a breathing room to the main fiber so other workers can be spawned
        process_queues(@queue)
      end
    end
        
    def create_threaded_worker
      Thread.new do
        queue = ::Ultralite::Queue.new(@options) # create new queue object
        process_queues(queue)
      end
    end
    
    
  end
end
