#require 'polyphony'
require 'async/scheduler'
require './bench'

Fiber.set_scheduler Async::Scheduler.new

count = 10000
require './skjob.rb'
require './uljob.rb'

puts Litesupport.environment

t = Time.now.to_f
puts "make sure sidekiq is started with skjob.rb as the job"     
bench("enqueuing sidekiq jobs", count) do |i|
  SidekiqJob.perform_async(count, t)
end

puts "Don't forget to check the sidekiq log for processing time conclusion"

t = Time.now.to_f
bench("enqueuing litejobs", count) do |i|
  MyJob.perform_async(count, t)
end

Fiber.scheduler.run

sleep

