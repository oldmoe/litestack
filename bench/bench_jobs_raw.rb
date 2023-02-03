require './bench'
require './skjob.rb'
require './uljob.rb'

count = 10000
t = Time.now.to_f
bench("ultralite jobs", count) do |i|
  UltraliteJob.perform_async(count, i+1, t)
end

sleep 7

# make sure sidekiq is started with skjob.rb as the job-     
bench("sidekiq jobs", count) do |i|
  SidekiqJob.perform_async(count, i+1, t)
end

