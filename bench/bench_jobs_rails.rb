require "./bench"

count = begin
  ARGV[0].to_i
rescue
  1000
end
env = ARGV[1] || "t"
delay = begin
  ARGV[2].to_f
rescue
  0
end

# ActiveJob::Base.logger = Logger.new(IO::NULL)

require "./rails_job"

RailsJob.queue_adapter = :sidekiq
t = Time.now.to_f
puts "Make sure sidekiq is started with -c ./rails_job.rb"
bench("enqueuing sidekiq jobs", count) do
  RailsJob.perform_later(count, t)
end

puts "Don't forget to check the sidekiq log for processing time conclusion"

# Litejob bench
###############

if env == "a" # threaded
  require "async/scheduler"
  Fiber.set_scheduler Async::Scheduler.new
  ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
end

require_relative "../lib/active_job/queue_adapters/litejob_adapter"
puts Litesupport.scheduler

RailsJob.queue_adapter = :litejob
t = Time.now.to_f
bench("enqueuing litejobs", count) do
  RailsJob.perform_later(count, t)
end

if env == "a" # threaded
  Fiber.scheduler.run
end

sleep
