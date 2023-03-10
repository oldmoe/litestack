# frozen_stringe_literal: true
require 'logger'
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
    queues: [["default", 1]],
    workers: 5,
    retries: 5, 
    retry_delay: 60,
    retry_delay_multiplier: 10,
    dead_job_retention: 10 * 24 * 3600,
    gc_sleep_interval: 7200, 
    logger: 'STDOUT',
    sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 1.0, 2.0]
  }
  
  @@queue = nil
  
  attr_reader :running
  
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
    config = YAML.load_file(@options[:config_path]) rescue {} # an empty hash won't hurt
    config.keys.each do |k| # symbolize keys
      config[k.to_sym] = config[k]
      config.delete k
    end
    @options.merge!(config)
    @options.merge!(options) # make sure options passed to initialize trump everything else

    @queue = Litequeue.new(@options) # create a new queue object
    
    # create logger
    if @options[:logger].respond_to? :info
      @logger = @options[:logger] 
    elsif @options[:logger] == 'STDOUT'
      @logger = Logger.new(STDOUT)      
    elsif @options[:logger] == 'STDERR'
      @logger = Logger.new(STDERR)      
    elsif @options[:logger].nil?
      @logger = Logger.new(IO::NULL)      
    elsif @options[:logger].is_a? String 
      @logger = Logger.new(@options[:logger])
    else
      @logger = Logger.new(IO::NULL)      
    end
    # group and order queues according to their priority
    pgroups = {}
    @options[:queues].each do |q|
      pgroups[q[1]] = [] unless pgroups[q[1]]
      pgroups[q[1]] << [q[0], q[2] == "spawn"]
    end
    @queues = pgroups.keys.sort.reverse.collect{|p| [p, pgroups[p]]}
    @running = true
    @workers = @options[:workers].times.collect{ create_worker }
    
    @gc = create_garbage_collector
    @jobs_in_flight = 0
    @mutex = Litesupport::Mutex.new
    
    at_exit do
      @running = false
      puts "--- Litejob detected an exit attempt, cleaning up"
      index = 0
      while @jobs_in_flight > 0 and index < 5
        puts "--- Waiting for #{@jobs_in_flight} jobs to finish"
        sleep 1
        index += 1
      end
      puts " --- Exiting with #{@jobs_in_flight} jobs in flight"
    end
  
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
    payload = Oj.dump({klass: jobclass, params: params, retries: @options[:retries], queue: queue})
    res = @queue.push(payload, delay, queue)
    @logger.info("[litejob]:[ENQ] id: #{res} job: #{jobclass}")
    res
  end
  
  # delete a job from the job queue
  #   class EasyJob
  #      def perform(any, number, of_params)
  #         # do anything
  #      end 
  #   end
  #   jobqueue = Litejobqueue.new
  #   id = jobqueue.push(EasyJob, params, 10) # queue for processing in 10 seconds
  #   jobqueue.delete(id, 'default')    
  def delete(id, queue=nil)
    job = @queue.delete(id, queue)
    @logger.info("[litejob]:[DEL] job: #{job}")
    job = Oj.load(job[0]) if job
    job
  end
  
  # delete all jobs in a certain named queue
  # or delete all jobs if the queue name is nil
  def clear(queue=nil)
    @queue.clear(queue)
  end
  
  # stop the queue object (does not delete the jobs in the queue)
  # specifically useful for testing
  def stop
    @running = false
    @@queue = nil
  end
  
  
  def count(queue=nil)
    @queue.count(queue)
  end
  
  private
  
  def job_started
    Litesupport.synchronize(@mutex){@jobs_in_flight += 1}
  end
  
  def job_finished
    Litesupport.synchronize(@mutex){@jobs_in_flight -= 1}
  end
  
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
      worker_sleep_index = 0
      while @running do
        processed = 0
        @queues.each do |level| # iterate through the levels
          level[1].each do |q| # iterate through the queues in the level
            index = 0
            max = level[0]
            while index < max && payload = @queue.pop(q[0], 1) # fearlessly use the same queue object 
              processed += 1
              index += 1
              begin
                id, job = payload[0], payload[1]
                job = Oj.load(job)
                # first capture the original job id                
                job[:id] = id if job[:retries].to_i == @options[:retries].to_i
                @logger.info "[litejob]:[DEQ] job:#{job}" 
                klass = eval(job[:klass])
                schedule(q[1]) do # run the job in a new context
                  job_started #(Litesupport.current_context)
                  begin
                    klass.new.perform(*job[:params])
                    @logger.info "[litejob]:[END] job:#{job}" 
                  rescue Exception => e
                    # we can retry the failed job now
                    if job[:retries] == 0
                      @logger.error "[litejob]:[ERR] job: #{job} failed with #{e}:#{e.message}, retries exhausted, moved to _dead queue"
                      @queue.push(Oj.dump(job), @options[:dead_job_retention], '_dead')
                    else
                      retry_delay = @options[:retry_delay_multiplier].pow(@options[:retries] - job[:retries]) * @options[:retry_delay] 
                      job[:retries] -=  1
                      @logger.error "[litejob]:[ERR] job: #{job} failed with #{e}:#{e.message}, retrying in #{retry_delay}"
                      @queue.push(Oj.dump(job), retry_delay, q[0])
                      @logger.info "[litejob]:[ENQ] job: #{job} enqueued"
                    end
                  end
                  job_finished #(Litesupport.current_context)
                end
              rescue Exception => e
                # this is an error in the extraction of job info
                # retrying here will not be useful
                @logger.error "[litejob]:[ERR] failed to extract job info for: #{payload} with #{e}:#{e.message}"
              end
              Litesupport.switch #give other contexts a chance to run here
            end
          end
        end
        if processed == 0 
          sleep @options[:sleep_intervals][worker_sleep_index]      
          worker_sleep_index += 1 if worker_sleep_index < @options[:sleep_intervals].length - 1          
        else
          worker_sleep_index = 0 # reset the index
        end
      end
    end
  end  
  
  # create a gc for dead jobs
  def create_garbage_collector
    Litesupport.spawn do
      while @running do
        while jobs = @queue.pop('_dead', 100)
          if jobs[0].is_a? Array
            @logger.info "[litejob]:[DEL] garbage collector deleted #{jobs.length} dead jobs"
          else
            @logger.info "[litejob]:[DEL] garbage collector deleted 1 dead job"
          end
        end
        sleep @options[:gc_sleep_interval]      
      end
    end
  end
  
end
