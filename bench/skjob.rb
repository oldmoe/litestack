require 'sidekiq'

class SidekiqJob
  include Sidekiq::Job
  @@count = 0
  def perform(count, time)
    sleep 0.1  
    @@count += 1
    if @@count == count  
      puts "finished in #{Time.now.to_f - time} seconds (#{count / (Time.now.to_f - time)} jps)"
    end
  end
end
