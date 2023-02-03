require './bench'
require 'ultralite'
require_relative '../lib/ultralite/job'

class UltraliteJob
  include Ultralite::Job

  def perform(count, index, time)
    puts "finished in #{Time.now.to_f - time}" if count == index
  end
end
