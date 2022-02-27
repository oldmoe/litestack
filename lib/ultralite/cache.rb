module Ultralite

	class Cache

		DEFAULT_EXPIRY = 60 * 60 * 24 * 30 # one month default expiry
		DEFAULT_SIZE = 128 * 1024 * 1024 # 128MB default size
		MIN_SIZE = 32 * 1024 * 1024
		DEFAULT_PATH = "./ultralite.cache"
		MAGIC_STR = '[^]'.freeze

		def initialize(path = DEFAULT_PATH, options = {})
			@path = path
			@size = options[:size].to_i rescue DEFAULT_SIZE
			@size = MIN_SIZE if @size < MIN_SIZE
			@expiry = options[:expiry] || DEFAULT_EXPIRY
			@cache = create_store(@path)
			prepare_statements
			@bgdb = create_store(@path)
			@bgthread = spawn_bg_thread(@bgdb) 
			@last_visited = ::Queue.new
		end

		def spawn_bg_thread(db)
			bg_thread = Thread.new do
				indexer = db.prepare("update data set indexed = 1, id = substr(id, 4) where id IN (select id from data where id like '#{MAGIC_STR}%' and indexed = 0 limit 1000)")
				pruner = db.prepare("delete from data where expires_on <= ? and indexed = 1")
				sizer = db.prepare("select sum(length(value)) from data where indexed = 1")
				toucher = db.prepare("update data set last_used = ? where id = ? ")
				extra_pruner = db.prepare("delete from data where indexed = 1 order by last_used asc limit (select cast((count(*)/5) as int) from data)")
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
							indexer.execute!
							#delete all expired entries
							pruner.execute! 						
						end
					rescue SQLite3::FullException
						extra_pruner.execute!
						db.execute("vacuum")
					end
				end
			end
		end

		def prepare_statements
			@setter = @cache.prepare("insert into data (id, value, size, expires_on, last_used) values ( '#{MAGIC_STR}' || ?, ?, ?, strftime('%s','now') + ?,  strftime('%s','now'))")
			@finder = @cache.prepare("select id from data where id = $1 or id = '#{MAGIC_STR}' || $1")
			@getter = @cache.prepare("select value from data where id = $1 or id = '#{MAGIC_STR}' || $1 and expires_on > strftime('%s','now') ")
			@updater = @cache.prepare("update data set value = ?, size = ?, expires_on = strftime('%s','now') + ?, last_used = strftime('%s','now'), indexed = 0	 where id = ?")
			@toucher = @cache.prepare("update data set last_used = strftime('%s','now') where id = ? and expires_on > strftime('%s','now') returning value")
			@deleter = @cache.prepare("delete from data where id = ?")
			@pruner = @cache.prepare("delete from data where expires_on <= ? and indexed = 1")
			@extra_pruner = @cache.prepare("delete from data where indexed = 1 order by last_used asc limit (select cast((count(*)/5) as int) from data)")
		end
		
		def create_store(path)
			db = SQLite3::Database.new(path)
			db.busy_handler{ sleep 0.0001 } 
			db.synchronous = 0
			db.cache_size = 2000
			db.execute("pragma journal_mode = WAL")
			db.journal_size_limit = [(@size/2).to_i, 32 * 1024 * 1024].min
			db.mmap_size = @size
			db.max_page_count = (@size / db.page_size).to_i + 250
			db.case_sensitive_like = true
			db.execute("create table if not exists data(id text primary key, value blob, size integer, expires_on integer, last_used integer, indexed integer default 0)")
			db.execute("create index if not exists expiry_index on data (expires_on) where indexed = 1")
			db.execute("create index if not exists last_used_index on data (last_used) where indexed = 1")
			db.execute("create index if not exists size_index on data (length(value)) where indexed = 1")
			db
		end
		
		def set(key, value, expires_after = nil)
			key = key.to_s
			expires_after = @expiry unless expires_after
			@cache.transaction :immediate do
				record = @finder.execute!(key)[0]
				begin
					if record
						key = record[0]
						@updater.execute!(value, value.length, expires_after, key)
					else
						@setter.execute!(key, value, value.length, expires_after)
					end
				rescue SQLite3::FullException
					@extra_pruner.execute!
					@cache.execute("vacuum")
					#retry
					return false
				end
			end
			return true
		end
		
		def get(key)
			key = key.to_s
			record = @getter.execute!(key)[0]
			if record
				@last_visited << key
				return record[0]
			end
			nil
		end
		
		def delete(key)
			@deleter.execute!(key)
		end
		
		def clear
			@cache.execute("delete from data")
			@cache.execute("vacuum")
		end
		
		def close
		end
	
	end
end
