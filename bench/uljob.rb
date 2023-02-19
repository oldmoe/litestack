require './bench'
require 'ultralite'

class UltraliteJob
  include Ultralite::Job
  @@count = 0
#  self.queue = :normal
  def perform(count, time)
    sleep 1
    @@count += 1
    if @@count == count  
      puts "UL finished in #{Time.now.to_f - time} seconds (#{count / (Time.now.to_f - time)} jps)"
    end
  end
end
