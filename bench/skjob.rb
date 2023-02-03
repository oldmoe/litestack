require 'sidekiq'

class SidekiqJob
  include Sidekiq::Job

  def perform(count, index, time)
    puts "finished in #{Time.now.to_f - time} seconds" if count == index
  end
end
