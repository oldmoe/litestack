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

# Sidekiq bench
###############
require "./skjob"

t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts "make sure sidekiq is started with skjob.rb as the job"
bench("enqueuing sidekiq jobs", count) do |i|
  SidekiqJob.perform_async(count, t, delay)
end

puts "Don't forget to check the sidekiq log for processing time conclusion"

# Litejob bench
###############

if env == "t" # threaded
  # do nothing
elsif env == "a" # async
  require "async/scheduler"
  Fiber.set_scheduler Async::Scheduler.new
end

require "./uljob"

warn "litejob started in #{Litesupport.scheduler} environmnet"

t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
bench("enqueuing litejobs", count) do |i|
  MyJob.perform_async(count, t, delay)
end

puts "Please wait for the benchmark to finish .."

Fiber.scheduler.run if env == "a"

sleep
