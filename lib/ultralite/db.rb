module Ultralite

	class DB < ::SQLite3::Database
		
		def initialize(file, options = {}, zfs = nil )
			if block_given?
				super(file, options, zfs) do |db|
					init unless options[:noinit] == true
					yield db				
				end
			else
				super(file, options, zfs) 
				init unless options[:noinit] == true
			end
		end
		
		def init
			self.busy_handler{|i| sleep 0.0001; true } 
			self.synchronous = 2
			self.journal_mode = "WAL"
			self.journal_size_limit = 128 * 1024 * 1024
			self.mmap_size = 128 * 1024 * 1024
			self.cache_size = 2000
		end
		
		# enforce immediate mode to avoid deadlocks for a small performance penalty
		def transaction(mode = :immediate)
			super(mode)
		end

	end

end
