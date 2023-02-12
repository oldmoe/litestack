require './bench'
require 'ultralite'

class UltraliteJob
  include Ultralite::Job
  @@count = 0
#  self.queue = :normal
  def perform(count, time)
    @@count += 1  
    if @@count == count  
      puts "finished in #{Time.now.to_f - time} seconds (#{count / (Time.now.to_f - time)} jps)"
      @@count = 0
    end
  end
end
