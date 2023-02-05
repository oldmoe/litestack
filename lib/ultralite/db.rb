module Ultralite

	# Ultralite DB inherits from the SQLite3::Database class and addes a few initialization options
	class DB < ::SQLite3::Database
		
		# overrride the original initilaizer to allow for connection configuration
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

		# enforce immediate mode to avoid deadlocks for a small performance penalty
		def transaction(mode = :immediate)
			super(mode)
		end
		
		private
		
		# default connection configuration values 
		def init
			# version 3.37 is requirede for strict typing support and the newest json operators
			raise Ultralite::Error if SQLite3::SQLITE_VERSION_NUMBER < 3037000
			# time to wait to obtain a write lock before raising an exception
			self.busy_handler{sleep 0.001} 
			# level of database durability, 2 = "FULL" (sync on every write), other values include 1 = "NORMAL" (sync every 1000 written pages) and 0 = "NONE"
			self.synchronous = 1 
			# Journal mode WAL allows for greater concurrency (many readers + one writer)
			self.journal_mode = "WAL"
			# impose a limit on the WAL file to prevent unlimited growth (with a negative impact on read performance as well)
			self.journal_size_limit = 64 * 1024 * 1024
			# set the global memory map so all processes can share data
			self.mmap_size = 128 * 1024 * 1024
			# increase the local connection cache to 2000 pages
			self.cache_size = 2000
		end
		
	end

end
