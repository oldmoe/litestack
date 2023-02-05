require './bench'
require './skjob.rb'
require './uljob.rb'

count = 100000

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

sleep
