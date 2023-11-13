require "lite_job/database_connection"
require "lite_job/runnable"
require "lite_job/job"
require "lite_job/worker"
require "lite_job/garbage_collector"
require "lite_job/resettable" if Litesupport.environment == "test"
require "lite_support/configurable"
require "forwardable"

module LiteJob
  include LiteSupport::Configurable
  include ::Litemetric::Measurable
  extend Runnable

  class << self
    extend Forwardable
    def_delegators 'LiteJob::Job', :pop, :enqueue, :count, :dead_count, :unassigned_count
  end

  @jobs_in_flight = 0
  @workers = []

  self.default_configuration = {
    queues: [["default", 1]],
    workers: 5,
    retries: 5,
    retry_delay: 60,
    retry_delay_multiplier: 10,
    dead_job_retention: 10 * 24 * 3600,
    gc_sleep_interval: 7200,
    jobs_assumed_dead_after: 60 * 30,
    logger: "STDOUT",
    sleep_intervals: [0.001, 0.005, 0.025, 0.125, 0.625, 1.0, 2.0],
    metrics: false
  }
  configures_from "./config/lite_job.yml"

  attr_reader :queues

  def self.metrics_identifier
    "LiteJob"
  end

  def self.logger
    @logger ||= create_logger
  end

  def self.create_logger
    LiteJob.configuration.logger = nil unless LiteJob.configuration.logger
    return LiteJob.configuration.logger if LiteJob.configuration.logger.respond_to? :info
    return Logger.new($stdout) if LiteJob.configuration.logger == "STDOUT"
    return Logger.new($stderr) if LiteJob.configuration.logger == "STDERR"
    return Logger.new(LiteJob.configuration.logger) if LiteJob.configuration.logger.is_a? String
    Logger.new(IO::NULL)
  end

  at_exit do
    kill
    if @jobs_in_flight > 0
      puts "--- Litejob detected an exit, cleaning up"
      sleeps = 0
      while @jobs_in_flight > 0 && sleeps < 30 # 3 seconds grace period for jobs to finish
        puts "--- Waiting for #{@jobs_in_flight} jobs to finish"
        sleep 0.1
        sleeps += 1
      end
      puts " --- Exiting with #{@jobs_in_flight} jobs in flight"
    end
  end

  run unless ENV["LITEJOB_NO_AUTORUN"] == "1"
end