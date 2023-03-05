require './bench'
require '../lib/litestack'

class MyJob
  include Litejob
  @@count = 0
  #self.queue = :default
  def perform(count, time, sleep_interval = nil)
    sleep sleep_interval if sleep_interval  
    @@count += 1
    if @@count == count  
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      STDERR.puts "Litejob finished in #{now - time} seconds (#{count / (now - time)} jps)"
    end
  end
end
