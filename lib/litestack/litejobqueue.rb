# frozen_stringe_literal: true

require 'oj'
require 'yaml'
require_relative './litequeue'

##
#Litejobqueue is a job queueing and processing system designed for Ruby applications. It is built on top of SQLite, which is an embedded relational database management system that is #lightweight and fast.
#
#One of the main benefits of Litejobqueue is that it is very low on resources, making it an ideal choice for applications that need to manage a large number of jobs without incurring #high resource costs. In addition, because it is built on SQLite, it is easy to use and does not require any additional configuration or setup.
#
#Litejobqueue also integrates well with various I/O frameworks like Async and Polyphony, making it a great choice for Ruby applications that use these frameworks. It provides a #simple and easy-to-use API for adding jobs to the queue and for processing them.
#
#Overall, LiteJobQueue is an excellent choice for Ruby applications that require a lightweight, embedded job queueing and processing system that is fast, efficient, and easy to use.
class Litejobqueue

  # the default options for the job queue
  # can be overriden by passing new options in a hash 
  # to Litejobqueue.new, it will also be then passed to the underlying Litequeue object
  #   config_path: "./litejob.yml" -> were to find the configuration file (if any)
  #   path: "./queue.db"
  #   mmap_size: 128 * 1024 * 1024 -> 128MB to be held in memory
  #   sync: 1 -> sync only when checkpointing
  #   queues: [["default", 1, "spawn"]] -> an array of queues to process 
  #   workers: 1 -> number of job processing workers
  #   sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 3.125] -> sleep intervals for workers
  # queues will be processed according to priority, such that if the queues are as such
  #   queues: [["default", 1, "spawn"], ["urgent", 10]]
  # it means that roughly, if the queues are full, for each 10 urgent jobs, 1 default job will be processed
  # the priority value is mandatory. The optional "spawn" parameter tells the job workers to spawn a separate execution context (thread or fiber, based on environment) for each job. 
  # This can be particularly useful for long running, IO bound jobs. It is not recommended though for threaded environments, as it can result in creating many threads that may consudme a lot of memory. 
  DEFAULT_OPTIONS = {
    config_path: "./litejob.yml",
    path: "./queue.db",
    queues: [["default", 5]],
    workers: 1,
    sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 3.125]
  }
  
  @@queue = nil
  
  # a method that returns a single instance of the job queue
  # for use by Litejob
  def self.jobqueue(options = {})
    @@queue ||= Litesupport.synchronize{self.new(options)}
  end

  def self.new(options = {})
    return @@queue if @@queue
    @@queue = allocate
    @@queue.send(:initialize, options)
    @@queue 
  end

  # create new queue instance (only once instance will be created in the process)
  #   jobqueue = Litejobqueue.new
  #   
  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)
    @worker_sleep_index = 0
    config = YAML.load_file(@options[:config_path]) rescue {} # an empty hash won't hurt
    config.keys.each do |k| # symbolize keys
      config[k.to_sym] = config[k]
      config.delete k
    end
    @options.merge!(config)
    @queue = Litequeue.new(@options) # create a new queue object
    # group and order queues according to their priority
    pgroups = {}
    @options[:queues].each do |q|
      pgroups[q[1]] = [] unless pgroups[q[1]]
      pgroups[q[1]] << [q[0], q[2] == "spawn"]
    end
    @queues = pgroups.keys.sort.reverse.collect{|p| [p, pgroups[p]]}
    @workers = @options[:workers].times.collect{create_worker} 
  end
  
  # push a job to the queue
  #   class EasyJob
  #      def perform(any, number, of_params)
  #         # do anything
  #      end 
  #   end
  #   jobqueue = Litejobqueue.new
  #   jobqueue.push(EasyJob, params) # the job will be performed asynchronously
  def push(jobclass, params, delay=0, queue=nil)
    payload = Oj.dump([jobclass, params])
    @queue.push(payload, delay, queue)
  end
  
  # delete a job from the job queue
  #   class EasyJob
  #      def perform(any, number, of_params)
  #         # do anything
  #      end 
  #   end
  #   jobqueue = Litejobqueue.new
  #   id = jobqueue.push(EasyJob, params, 10) # queue for processing in 10 seconds
  #   jobqueue.delete(id)    
  def delete(id)
    job = @queue.delete(id)
    Oj.load(job) if job
  end
  
  private
  
  # optionally run a job in its own context
  def schedule(spawn = false, &block)
    if spawn
      Litesupport.spawn &block
    else
      yield
    end
  end
  
  # create a worker according to environment
  def create_worker
    Litesupport.spawn do
      # we create a queue object specific to this worker here
      # this way we can survive potential SQLite3 Database is locked errors
      queue = Litequeue.new(@options)
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
              Litesupport.switch #give other context a chance to run here
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
  end     
  
end
