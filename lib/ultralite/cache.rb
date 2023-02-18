# frozen_stringe_literal: true

module Ultralite

	class Cache

		DEFAULT_EXPIRY = 60 * 60 * 24 * 30 # one month default expiry
		DEFAULT_SIZE = 128 * 1024 * 1024 # 128MB default size
		MIN_SIZE = 32 * 1024 # 32MB minimum cache size
		DEFAULT_PATH = "./ultralite.cache"

		def initialize(options = {})
			@path = options[:path] || DEFAULT_PATH
			@size = options[:size].to_i rescue DEFAULT_SIZE
			@size = MIN_SIZE if @size < MIN_SIZE
			@expires_in = options[:expires_in] || DEFAULT_EXPIRY
			@return_full_record = options[:return_full_record]
			@sql = {
			  :pruner => "DELETE FROM data WHERE expires_in <= $1",
			  :extra_pruner => "DELETE FROM data WHERE id IN (SELECT id FROM data ORDER BY last_used ASC LIMIT (SELECT CAST((count(*) * $1) AS int) FROM data))",
			  :limited_pruner => "DELETE FROM data WHERE id IN (SELECT id FROM data ORDER BY last_used asc limit $1)",
			  :toucher => "UPDATE data SET  last_used = unixepoch('now') WHERE id = $1",
		  	:setter => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in",
			  :inserter => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in WHERE id = $1 and expires_in <= unixepoch('now')",
			  :finder => "SELECT id FROM data WHERE id = $1",
			  :getter => "SELECT id, value, expires_in FROM data WHERE id = $1",# AND expires_in >= strftime('%s','now')",
			  :deleter => "delete FROM data WHERE id = $1 returning value",
			  :incrementer => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = cast(value AS int) + cast(excluded.value as int), last_used = excluded.last_used, expires_in = excluded.expires_in",
  			:counter => "SELECT count(*) FROM data",
		  	:sizer => "SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count"
			  
			}
			@stats = {hit: 0, miss: 0}
			@cache = create_store(@path)
			prepare_statements
			@last_visited = {}
			@bgthread = spawn_bg_worker(@cache, @sql) 
		  @sql = nil #discard all the sql strings
		end

    def spawn_bg_worker(db, sql)
      #if Ultralite.environment == :fiber_scheduler
      #  spawn_fiber_scheduler_worker(db, sql)
      #elsif Ultralite.environment == :polyphony
      #  spawn_polyphony_worker(db, sql)
      #else
  			db = create_store(@path)
        spawn_threaded_worker(db, sql)
      #end           
    end

    def spawn_polyhpony_worker(db, sql)    
			spin do
				round = 0
				loop do
					sleep 1
					begin
						db.transaction(:immediate) do
							@last_visited.delete_if do |k|
							  @toucher.execute!(k) || true
							end
							@pruner.execute! 						
						end
					rescue SQLite3::FullException
						@extra_pruner.execute!(0.2)
					end
				end
			end
    end
    
    def spawn_fiber_scheduler_worker(db, sql)
			Fiber.schedule do
				loop do
					sleep 1
					begin
						db.transaction(:immediate) do
							@last_visited.delete_if do |k|
							  @toucher.execute!(k) || true
							end
							@pruner.execute! 						
						end
					rescue SQLite3::FullException
						@extra_pruner.execute!(0.2)
					end
				end
			end
    end

		def spawn_threaded_worker(db, sql)
			bg_thread = Thread.new do
				pruner = db.prepare(sql[:pruner])
				toucher = db.prepare(sql[:toucher])
				extra_pruner = db.prepare(sql[:extra_pruner])
				loop do
					sleep 1
					begin
						db.transaction(:immediate) do
							@last_visited.delete_if do |k|
							  toucher.execute!(k) || true
							end
							pruner.execute! 						
						end
					rescue SQLite3::FullException
						extra_pruner.execute!(0.2)
					end
				end
			end
		end

		def prepare_statements
		  @sql.each_pair do |k, v|
		    self.instance_variable_set("@#{k.to_s}", @cache.prepare(v))
		  end
		end
		
		def create_store(path)
			db = SQLite3::Database.new(path)
			db.busy_handler{|i| sleep 0.0001 } 
			db.synchronous = 0
			db.cache_size = 2000
			db.execute("pragma journal_mode = WAL")
			db.journal_size_limit = [(@size/2).to_i, MIN_SIZE].min
			db.mmap_size = @size
			db.max_page_count = @size 
			db.case_sensitive_like = true
			db.execute("CREATE table if not exists data(id text primary key, value text, expires_in integer, last_used integer)")
			db.execute("CREATE index if not exists expiry_index on data (expires_in)")
			db.execute("CREATE index if not exists last_used_index on data (last_used)")
			db
		end
				
		def set(key, value, expires_in = nil)
			key = key.to_s
			expires_in = @expires_in if expires_in.nil? or expires_in.zero?
			begin
			  @setter.execute!(key, value, expires_in)
			rescue SQLite3::FullException
			  @extra_pruner.execute!(0.2)
				@cache.execute("vacuum")
				retry
			end
			return true
		end
		
		def set_unless_exists(key, value, expires_in = nil)
			key = key.to_s
			expires_in = @expires_in if expires_in.nil? or expires_in.zero?
			begin
			  transaction(:immediate) do
				  @inserter.execute!(key, value, expires_in)
				  changes = @cache.changes
				end
			rescue SQLite3::FullException
			  @extra_pruner.execute!(0.2)
				@cache.execute("vacuum")
				retry
			end
			return changes > 0
		end
		
		def get(key)
      key = key.to_s
			record = @getter.execute!(key)[0]
			if record
				@last_visited[key] = true
				@stats[:hit] +=1
				return record[1]
			end
			@stats[:miss] += 1
			nil
		end
		
		def delete(key)
			@deleter.execute!(key)
			return @cache.changes > 0
		end
		
		def increment(key, amount, expires_in = nil)
			expires_in = @expires_in unless expires_in
			@incrementer.execute!(key.to_s, amount, expires_in)
		end
		
		def decrement(key, amount, expires_in = nil)
			increment(key, -amount, expires_in)
		end
		
		def prune(limit=nil)
		  if limit and limit.is_a? Integer
		    @limited_pruner.execute!(limit)
		  elsif limit and limit.is_a? Float
		    @extra_pruner.execute!(limit)
		  else
		    @pruner.execute!		  
		  end
		end
		
		def count
		  @counter.execute!.to_a[0][0]
		end
		
		def size
      @sizer.execute!.to_a[0][0]
		end
		
		def clear
			@cache.execute("delete FROM data")
			#@cache.execute("vacuum")
		end
		
		def close
		  @cache.close
		end
		
		def max_size
		  @cache.get_first_value("SELECT s.page_size * c.max_page_count FROM pragma_page_size() as s, pragma_max_page_count() as c")
		end
		
		def stats
		  @stats
		end
		
		def transaction(mode)
		  @cache.transaction(mode) do
		    yield
		  end
		end
	
	end
end
