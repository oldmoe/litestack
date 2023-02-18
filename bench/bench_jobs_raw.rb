require './bench'
require './skjob.rb'
require './uljob.rb'
#require 'polyphony'
#require 'async'
require 'async/scheduler'

Fiber.set_scheduler Async::Scheduler.new


puts "Ultralite: #{Ultralite.environment} environment detected!"

count = 10000

t = Time.now.to_f

# make sure sidekiq is started with skjob.rb as the job-     
bench("enqueuing sidekiq jobs", count) do |i|
  SidekiqJob.perform_async(count, t)
end

puts "Don't forget to check the sidekiq log for processing time conclusion"

t = Time.now.to_f
bench("enqueuing ultralite jobs", count) do |i|
  UltraliteJob.perform_async(count, t)
end

Fiber.scheduler.run

sleep

