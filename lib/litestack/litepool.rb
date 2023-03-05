# frozen_stringe_literal: true

# all components should require the support module
require_relative 'litesupport'

class Litepool
  
  def initialize(count, &block)
    @count = count
    @block = block
    @resources = []
    @mutex = Litesupport::Mutex.new
    @count.times do
      resource = @mutex.synchronize{ block.call }
      @resources << [resource, :free]
    end
  end
  
  def acquire
    acquired = false
    while !acquired do
      @mutex.synchronize do
        if resource = @resources.find{|r| !r[1] == :free}
          resource[1] = :busy
          yield resource[0]
          resource[1] = :free
          acquired = true
        end
      end
      puts "failed to acquire, sleeping"
      sleep 0.001 if trying 
    end
  end
  
end
