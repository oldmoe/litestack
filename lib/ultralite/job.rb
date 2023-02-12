require 'ultralite'
require_relative './job_queue'

module Ultralite
	
	module Job
	
	  def self.included(klass)
      klass.extend(ClassMethods)
	  end
	  
	  module ClassMethods
	    def perform_async(*params)
	      get_queue.push(self.name, params, 0, queue)	    
	    end
	    
	    def perform_at(time, *params)
	      delay = time - Time.now.to_i
	      get_queue.push(self.name, params, delay, queue)	         
	    end
	    
	    def perfrom_in(delay, *params)
	      get_queue.push(self.name, params, delay, queue)	         
	    end
	    
	    def mutex
	      @@mutex ||= Mutex.new
	    end
	    
	    def options
        @@options ||= {}
	    end
	    
	    def options=(options)
        @@options = options
      end
      
      def queue
        @@queue ||= "default"
      end
      
      def queue=(queue)
        @@queue = queue.to_s
      end
      	    
	    def get_queue
	      unless $_ul_queue 
    	    mutex.synchronize do
    	      # we need to have a queue per queue path, rather than one global queue
	          $_ul_queue = ::Ultralite::JobQueue.new(options) unless $_ul_queue
	        end
	      end
	      $_ul_queue
	    end
    end
    	
	end	
	
end
