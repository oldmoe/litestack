# frozen_stringe_literal: true

require_relative "litequeue"
require_relative "litemetric"

##
# Litejobqueue is a job queueing and processing system designed for Ruby applications. It is built on top of SQLite, which is an embedded relational database management system that is #lightweight and fast.
#
# One of the main benefits of Litejobqueue is that it is very low on resources, making it an ideal choice for applications that need to manage a large number of jobs without incurring #high resource costs. In addition, because it is built on SQLite, it is easy to use and does not require any additional configuration or setup.
#
# Litejobqueue also integrates well with various I/O frameworks like Async and Polyphony, making it a great choice for Ruby applications that use these frameworks. It provides a #simple and easy-to-use API for adding jobs to the queue and for processing them.
#
# Overall, LiteJobQueue is an excellent choice for Ruby applications that require a lightweight, embedded job queueing and processing system that is fast, efficient, and easy to use.
class Litejobqueue < Litequeue
  include Litemetric::Measurable

  # the default options for the job queue
  # can be overridden by passing new options in a hash
  # to Litejobqueue.new, it will also be then passed to the underlying Litequeue object
  #   config_path: "./litejob.yml" -> were to find the configuration file (if any)
  #   path: "./db/queue.db"
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
    path: Litesupport.root.join("queue.sqlite3"),
    queues: [["default", 1]],
    workers: 5,
    retries: 5,
    retry_delay: 60,
    retry_delay_multiplier: 10,
    dead_job_retention: 10 * 24 * 3600,
    gc_sleep_interval: 7200,
    logger: "STDOUT",
    sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 1.0, 2.0],
    metrics: false
  }

  @@queue = nil
  @@mutex = Litescheduler::Mutex.new

  attr_reader :running

  alias_method :_push, :push

  # a method that returns a single instance of the job queue
  # for use by Litejob
  def self.jobqueue(options = {})
    @@queue ||= @@mutex.synchronize { new(options) }
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
    @queues = [] # a place holder to allow workers to process
    super(options)

    # group and order queues according to their priority
    pgroups = {}
    @options[:queues].each do |q|
      pgroups[q[1]] = [] unless pgroups[q[1]]
      pgroups[q[1]] << [q[0], q[2] == "spawn"]
    end
    @queues = pgroups.keys.sort.reverse.collect { |p| [p, pgroups[p]] }
    collect_metrics if @options[:metrics]
  end

  def metrics_identifier
    "Litejob" # overrides default identifier
  end

  # push a job to the queue
  #   class EasyJob
  #      def perform(any, number, of_params)
  #         # do anything
  #      end
  #   end
  #   jobqueue = Litejobqueue.new
  #   jobqueue.push(EasyJob, params) # the job will be performed asynchronously
  def push(jobclass, params, delay = 0, queue = nil)
    payload = Oj.dump({klass: jobclass, params: params, retries: @options[:retries], queue: queue}, mode: :strict)
    res = super(payload, delay, queue)
    capture(:enqueue, queue)
    @logger.info("[litejob]:[ENQ] queue:#{res[1]} class:#{jobclass} job:#{res[0]}")
    res
  end

  def repush(id, job, delay = 0, queue = nil)
    res = super(id, Oj.dump(job, mode: :strict), delay, queue)
    capture(:enqueue, queue)
    @logger.info("[litejob]:[ENQ] queue:#{res[0]} class:#{job[:klass]} job:#{id}")
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
  #   jobqueue.delete(id)
  def delete(id)
    job = super(id)
    @logger.info("[litejob]:[DEL] job: #{job}")
    job = Oj.load(job[0], symbol_keys: true) if job
    job
  end

  # delete all jobs in a certain named queue
  # or delete all jobs if the queue name is nil
  # def clear(queue=nil)
  # @queue.clear(queue)
  # end

  # stop the queue object (does not delete the jobs in the queue)
  # specifically useful for testing
  def stop
    @running = false
    # @@queue = nil
    close
  end

  private

  def prepare_search_options(opts)
    sql_opts = super(opts)
    sql_opts[:klass] = opts[:klass]
    sql_opts[:params] = opts[:params]
    sql_opts
  end

  def exit_callback
    @running = false # stop all workers
    if @jobs_in_flight > 0
      puts "--- Litejob detected an exit, cleaning up"
      index = 0
      while @jobs_in_flight > 0 && index < 30 # 3 seconds grace period for jobs to finish
        puts "--- Waiting for #{@jobs_in_flight} jobs to finish"
        sleep 0.1
        index += 1
      end
      puts " --- Exiting with #{@jobs_in_flight} jobs in flight"
    end
  end

  def setup
    super
    @jobs_in_flight = 0
    @workers = @options[:workers].times.collect { create_worker }
    @gc = create_garbage_collector
    @mutex = Litescheduler::Mutex.new # reinitialize a mutex in setup as the environment could change after forking
  end

  def job_started
    @mutex.synchronize { @jobs_in_flight += 1 }
  end

  def job_finished
    @mutex.synchronize { @jobs_in_flight -= 1 }
  end

  # optionally run a job in its own context
  def schedule(spawn = false, &block)
    if spawn
      Litescheduler.spawn(&block)
    else
      yield
    end
  end

  # create a worker according to environment
  def create_worker
    # temporarily stop this feature until a better solution is implemented
    # return if defined?(Rails) && !defined?(Rails::Server)
    Litescheduler.spawn do
      worker_sleep_index = 0
      while @running
        processed = 0
        @queues.each do |priority, queues| # iterate through the levels
          queues.each do |queue, spawns| # iterate through the queues in the level
            batched = 0

            while (batched < priority) && (payload = pop(queue, 1)) # fearlessly use the same queue object
              capture(:dequeue, queue)
              processed += 1
              batched += 1

              id, serialized_job = payload
              process_job(queue, id, serialized_job, spawns)

              Litescheduler.switch # give other contexts a chance to run here
            end
          end
        end
        if processed == 0
          sleep @options[:sleep_intervals][worker_sleep_index]
          worker_sleep_index += 1 if worker_sleep_index < (@options[:sleep_intervals].length - 1)
        else
          worker_sleep_index = 0 # reset the index
        end
      end
    end
  end

  # create a gc for dead jobs
  def create_garbage_collector
    Litescheduler.spawn do
      while @running
        while (jobs = pop("_dead", 100))
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

  def process_job(queue, id, serialized_job, spawns)
    job = Oj.load(serialized_job)
    @logger.info "[litejob]:[DEQ] queue:#{queue} class:#{job["klass"]} job:#{id}"
    klass = Object.const_get(job["klass"])
    schedule(spawns) do # run the job in a new context
      job_started # (Litesupport.current_context)
      begin
        measure(:perform, queue) { klass.new.perform(*job["params"]) }
        @logger.info "[litejob]:[END] queue:#{queue} class:#{job["klass"]} job:#{id}"
      rescue Exception => e # standard:disable Lint/RescueException
        # we can retry the failed job now
        capture(:fail, queue)
        if job["retries"] == 0
          @logger.error "[litejob]:[ERR] queue:#{queue} class:#{job["klass"]} job:#{id} failed with #{e}:#{e.message}, retries exhausted, moved to _dead queue"
          repush(id, job, @options[:dead_job_retention], "_dead")
        else
          capture(:retry, queue)
          retry_delay = @options[:retry_delay_multiplier].pow(@options[:retries] - job["retries"]) * @options[:retry_delay]
          job["retries"] -= 1
          @logger.error "[litejob]:[ERR] queue:#{queue} class:#{job["klass"]} job:#{id} failed with #{e}:#{e.message}, retrying in #{retry_delay} seconds"
          repush(id, job, retry_delay, queue)
        end
      end
      job_finished # (Litesupport.current_context)
    end
  rescue Exception => e # standard:disable Lint/RescueException
    # this is an error in the extraction of job info, retrying here will not be useful
    @logger.error "[litejob]:[ERR] failed to extract job info for: #{serialized_job} with #{e}:#{e.message}"
    job_finished # (Litesupport.current_context)
  end
end
