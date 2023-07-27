module ActiveRecord
  module Patches
    module SQLite3Adapter
      def initialize(...)
        # version 3.37 is required for strict typing support and the newest json operators
        raise Litestack::InsufficientSQLiteVersionError if ::SQLite3::SQLITE_VERSION_NUMBER < 3037000
        
        super
        
        configure_connection unless options.fetch(:noinit, false)
        
        ::SQLite3::Database.prepend Litedb
        ::SQLite3::Statement.prepend Litedb::Statement
      end
      
      private
      
      def configure_connection
        # time to wait to obtain a write lock before raising an exception
        # https://www.sqlite.org/pragma.html#pragma_busy_timeout
        raw_connection.busy_handler { sleep 0.001 }
        
        # level of database durability, 2 = "FULL" (sync on every write), other values include 1 = "NORMAL" (sync every 1000 written pages) and 0 = "NONE"
        # https://www.sqlite.org/pragma.html#pragma_synchronous
        raw_connection.synchronous = "NORMAL"
        
        # Journal mode WAL allows for greater concurrency (many readers + one writer)
        # https://www.sqlite.org/pragma.html#pragma_journal_mode
        raw_connection.journal_mode = "WAL"
        
        # impose a limit on the WAL file to prevent unlimited growth (with a negative impact on read performance as well)
        # https://www.sqlite.org/pragma.html#pragma_journal_size_limit
        raw_connection.journal_size_limit = 64 * 1024 * 1024
        
        # set the global memory map so all processes can share data
        # https://www.sqlite.org/pragma.html#pragma_mmap_size
        # https://www.sqlite.org/mmap.html
        raw_connection.mmap_size = 128.megabytes
        
        # increase the local connection cache to 2000 pages
        # https://www.sqlite.org/pragma.html#pragma_cache_size
        raw_connection.cache_size = 2000
      end
    end
  end
end
