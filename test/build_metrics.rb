require_relative '../lib/litestack/litemetric'
require_relative '../lib/litestack/litecache'
require_relative '../lib/litestack/litejob'


# initialize the litemetric to modify the date function

lm = Litemetric.instance

# initialize the queue to capture the options
jobqueue = Litejobqueue.new({
  path: "./q.db", 
  retries: 2, 
  queues: [['normal', 1], ['urgent', 3], ['critical', 10]], 
  metrics: true,
  log: nil
})


$time = Time.now.to_i #- 10800
$start_time = Time.now.to_i

class NormalJob
  include Litejob
  self.queue = 'normal'
  def perform(time)
    $time = time #-= (rand * 100).to_i #10 seconds in the past
    sleep 0.001
    STDERR.puts "performing some normal action"
  end 
  
end

class SlowJob
  include Litejob
  self.queue = 'normal'
  
  def perform(time)
    $time = time  #(rand * 100).to_i #10 seconds in the past
    sleep 0.1
    STDERR.puts "performing some slow action"
  end 

end



class CriticalJob
  include Litejob
  self.queue = 'critical'
  
  def perform(time)
    $time = time  #(rand * 100).to_i #10 seconds in the past
    sleep 0.01
    STDERR.puts "performing some critical action"
  end 
  
end


class UrgentJob
  include Litejob
  self.queue = 'urgent'
  
  def perform(time)
    $time = time #(rand * 100).to_i #10 seconds in the past
    sleep 0.001
    STDERR.puts "performing some urgent action"
  end 
  
end

cache = Litecache.new({metrics: true})


def lm.current_time_slot
  ($time / 300) * 300
end

jobs = [SlowJob, UrgentJob, NormalJob, CriticalJob]

payload = "A"*128
setter = Proc.new{cache.set((rand * 1000).to_i.to_s, payload)}
getter = Proc.new{cache.get((rand * 1300).to_i.to_s)}
cache_actions = [getter]*5
cache_actions << setter

t = Time.now
5000.times do |i|
  $time = $start_time - (rand * (3600*24*7*52)).to_i #up to 52 weeks in the past
  jobs.sample.perform_async($time)
  cache_actions.sample.call
  puts "Finished #{i} events after #{Time.now - t} seconds for time_slot=#{lm.send(:current_time_slot)}" if i % 1000 == 0 and i > 0
end
puts "finished creating jobs, now summarizing"
lm.summarize
sleep 


