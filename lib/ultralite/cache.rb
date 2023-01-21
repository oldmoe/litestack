# frozen_stringe_literal: true

module Ultralite

	class Cache

		DEFAULT_EXPIRY = 60 * 60 * 24 * 30 # one month default expiry
		DEFAULT_SIZE = 128 * 1024 * 1024 # 128MB default size
		MIN_SIZE = 64 #* 1024 # 32MB minimum cache size
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
			  :toucher => "UPDATE data SET  last_used = $1 WHERE id = $2",
		  	:setter => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, strftime('%s','now') + $3,  strftime('%s','now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in",
			  :INSERTer => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, strftime('%s','now') + $3,  strftime('%s','now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in WHERE id = $1 and expires_in <  strftime('%s','now')",
			  :finder => "SELECT id FROM data WHERE id = $1",
			  :getter => "SELECT id, value, expires_in FROM data WHERE id = $1 AND expires_in > strftime('%s','now')",
			  :deleter => "delete FROM data WHERE id = $1 returning value",
			  :incrementer => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, strftime('%s','now') + $3, strftime('%s','now')) on conflict(id) do UPDATE SET value = cast(value AS int) + cast(excluded.value as int), last_used = excluded.last_used, expires_in = excluded.expires_in",
  			:counter => "SELECT count(*) FROM data",
		  	:sizer => "SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count"
			  
			}
			@cache = create_store(@path)
			prepare_statements
			@bgdb = create_store(@path)
			@last_visited = ::Queue.new
			@bgthread = spawn_bg_thread(@bgdb, @sql) 
		  @sql = nil #discard all the sql strings
		end

		def spawn_bg_thread(db, sql)
			bg_thread = Thread.new do
				pruner = db.prepare(sql[:pruner])
				toucher = db.prepare(sql[:toucher])
				extra_pruner = db.prepare(sql[:extra_pruner])
				round = 0
				loop do
					sleep 1
					time = Time.now.to_i
					round += 1
					begin
						db.transaction(:immediate) do
							keys = {}
							while not @last_visited.empty?
								keys[@last_visited.pop] = true
							end
							keys.each{|k, v| toucher.execute!(time, k)}
							# move new entries to the indexed state in bulk 1000 at a time
							#indexer.execute!
							#delete all expired entries
							pruner.execute! 						
						end
					rescue SQLite3::FullException
						extra_pruner.execute!(0.2)
						db.execute("vacuum")
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
			db.busy_handler{ sleep 0.0001 } 
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
			expires_in = @expires_in unless expires_in
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
			expires_in = @expires_in unless expires_in
			begin
				@INSERTer.execute!(key, value, expires_in)
				changes = @cache.changes
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
				@last_visited << key
				return record[1]
			end
			nil
		end
		
		def delete(key)
			@deleter.execute!(key)
			return @cache.changes > 0
		end
		
		def increment(key, amount, expires_in = nil)
			@incrementer.execute!(key.to_s, amount, expires_in ||= @expires_in)
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
			@cache.execute("vacuum")
		end
		
		def close
		  @cache.close
		end
		
		def max_size
		  @cache.get_first_value("SELECT s.page_size * c.max_page_count FROM pragma_page_size() as s, pragma_max_page_count() as c")
		end
		
		def transaction(mode)
		  @cache.transaction(mode) do
		    yield
		  end
		end
	
	end
end
