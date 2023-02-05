require 'ultralite'
require_relative './job_queue'

module Ultralite
	
	module Job
	
	  def self.included(klass)
      klass.extend(ClassMethods)
	  end
	  
	  module ClassMethods
	    def perform_async(*params)
	      get_queue.push(self.name, params)	    
	    end
	    
	    def perform_at(time, *params)
	      delya = time - Time.now.to_i
	      get_queue.push(self.name, params, delay, queue)	         
	    end
	    
	    def perfrom_in(delay, *params)
	      get_queue.push(self.name, params, delay, queue)	         
	    end
	    
	    def mutex
	      @@mutex ||= Mutex.new
	    end
	    
	    def get_queue
	      unless $_ul_queue 
    	    mutex.synchronize do
	          $_ul_queue = ::Ultralite::JobQueue.new
	        end
	      end
	      $_ul_queue
	    end
    end
    	
	end	
	
end
