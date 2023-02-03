require 'ultralite'
require_relative './job_queue'

module Ultralite
	
	module Job
	
	  def self.included(klass)
      klass.extend(ClassMethods)
      puts "I WAS INCLUDED"
	  end
	  
	  module ClassMethods
	    def perform_async(params, delay, queue)
	      get_queue.push(self.name, params, delay, queue)	    
	    end
	    
	    def perform_at(time, *params)
	      get_queue.push(self.name, params, delay, queue)	         
	    end
	    
	    def perfrom_in(delay, *params)
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
