require './bench'
require './rails_job.rb'
require 'ultralite'
require 'active_job/queue_adapters/ultralite_adapter'

count = 10000

RailsJob.queue_adapter = :ultralite
t = Time.now.to_f
bench("enqueuing ultralite jobs", count) do 
  RailsJob.perform_later(count, t)
end

sleep 5

RailsJob.queue_adapter = :sidekiq
t = Time.now.to_f
# make sure sidekiq is started with rails_job.rb as the job-     
bench("enqueuing sidekiq jobs", count) do 
  RailsJob.perform_later(count, t)
end

puts "Don't forget to check the sidekiq log for processing time conclusion"

