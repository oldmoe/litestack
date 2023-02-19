require './bench'
require './rails_job.rb'

puts "IN BENCH JOBS"

require_relative '../lib/active_job/queue_adapters/ultralite_adapter'


require 'async/scheduler'

ActiveJob::Base.logger = Logger.new(IO::NULL)

Fiber.set_scheduler Async::Scheduler.new

  count = 1000

  RailsJob.queue_adapter = :sidekiq
  t = Time.now.to_f
  puts "Make sure sidekiq is started with -c ./rails_job.rb"     
  bench("enqueuing sidekiq jobs", count) do 
    RailsJob.perform_later(count, t)
  end

  puts "Don't forget to check the sidekiq log for processing time conclusion"

  RailsJob.queue_adapter = :ultralite
  t = Time.now.to_f
  bench("enqueuing ultralite jobs", count) do 
    RailsJob.perform_later(count, t)
  end

Fiber.scheduler.run

sleep
