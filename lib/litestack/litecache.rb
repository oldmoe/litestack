# frozen_stringe_literal: true

# all components should require the support module
require_relative 'litesupport'
require_relative 'litemetric'

##
#Litecache is a caching library for Ruby applications that is built on top of SQLite. It is designed to be simple to use, very fast, and feature-rich, providing developers with a reliable and efficient way to cache data.
#
#One of the main features of Litecache is automatic key expiry, which allows developers to set an expiration time for each cached item. This ensures that cached data is automatically removed from the cache after a certain amount of time has passed, reducing the risk of stale data being served to users.
#
#In addition, Litecache supports LRU (Least Recently Used) removal, which means that if the cache reaches its capacity limit, the least recently used items will be removed first to make room for new items. This ensures that the most frequently accessed data is always available in the cache.
#
#Litecache also supports integer value increment/decrement, which allows developers to increment or decrement the value of a cached item in a thread-safe manner. This is useful for implementing counters or other types of numerical data that need to be updated frequently.
#
#Overall, Litecache is a powerful and flexible caching library that provides automatic key expiry, LRU removal, and integer value increment/decrement capabilities. Its fast performance and simple API make it an excellent choice for Ruby applications that need a reliable and efficient way to cache data.

class Litecache

  include Litesupport::Liteconnection
  include Litemetric::Measurable

  # the default options for the cache
  # can be overriden by passing new options in a hash 
  # to Litecache.new
  #   path: "./cache.db"
  #   expiry: 60 * 60 * 24 * 30 -> one month default expiry if none is provided
  #   size: 128 * 1024 * 1024 -> 128MB 
  #   mmap_size: 128 * 1024 * 1024 -> 128MB to be held in memory
  #   min_size: 32 * 1024 -> 32MB
  #   return_full_record: false -> only return the payload
  #   sleep_interval: 1 -> 1 second of sleep between cleanup runs

  DEFAULT_OPTIONS = {
    path: "./cache.db",
    sync: 0,
    expiry: 60 * 60 * 24 * 30, # one month 
    size: 128 * 1024 * 1024, #128MB 
    mmap_size: 128 * 1024 * 1024, #128MB
    min_size: 32 * 1024, #32MB
    return_full_record: false, #only return the payload
    sleep_interval: 1, # 1 second
    metrics: true
  }
  
  # creates a new instance of Litecache
  # can optionally receive an options hash which will be merged
  # with the DEFAULT_OPTIONS (the new hash overrides any matching keys in the default one).
  #
  # Example:
  #   litecache = Litecache.new
  #
  #   litecache.set("a", "somevalue")
  #   litecache.get("a") # =>  "somevalue"
  #
  #   litecache.set("b", "othervalue", 1) # expire aftre 1 second
  #   litecache.get("b") # => "othervalue"
  #   sleep 2
  #   litecache.get("b") # => nil
  #
  #   litecache.clear # nothing remains in the cache
  #   litecache.close # optional, you can safely kill the process
  
  def initialize(options = {})

    @sql = {
      :pruner => "DELETE FROM data WHERE expires_in <= $1",
      :extra_pruner => "DELETE FROM data WHERE id IN (SELECT id FROM data ORDER BY last_used ASC LIMIT (SELECT CAST((count(*) * $1) AS int) FROM data))",
      :limited_pruner => "DELETE FROM data WHERE id IN (SELECT id FROM data ORDER BY last_used asc limit $1)",
      :toucher => "UPDATE data SET  last_used = unixepoch('now') WHERE id = $1",
      :setter => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in",
      :inserter => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = excluded.value, last_used = excluded.last_used, expires_in = excluded.expires_in WHERE id = $1 and expires_in <= unixepoch('now')",
      :finder => "SELECT id FROM data WHERE id = $1",
      :getter => "SELECT id, value, expires_in FROM data WHERE id = $1",
      :deleter => "delete FROM data WHERE id = $1 returning value",
      :incrementer => "INSERT into data (id, value, expires_in, last_used) VALUES   ($1, $2, unixepoch('now') + $3, unixepoch('now')) on conflict(id) do UPDATE SET value = cast(value AS int) + cast(excluded.value as int), last_used = excluded.last_used, expires_in = excluded.expires_in",
      :counter => "SELECT count(*) FROM data",
      :sizer => "SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count" 
    }
  
    init(options)
    
    #@options = DEFAULT_OPTIONS.merge(options)
    @options[:size] = @options[:min_size] if @options[:size] < @options[:min_size]
        
    #@cache = Litesupport::Pool.new(1){create_db}
    @last_visited = {}
    #@running = true
    collect_metrics if @options[:metrics]
  end
  
  # add a key, value pair to the cache, with an optional expiry value (number of seconds)      
  def set(key, value, expires_in = nil)
    key = key.to_s
    expires_in = @options[:expires_in] if expires_in.nil? or expires_in.zero?
    @conn.acquire do |cache|
      begin
        cache.stmts[:setter].execute!(key, value, expires_in)
        capture(:write)
      rescue SQLite3::FullException
        cache.stmts[:extra_pruner].execute!(0.2)
        cache.execute("vacuum")
        retry
      end
    end
    return true
  end
  
  # add a key, value pair to the cache, but only if the key doesn't exist, with an optional expiry value (number of seconds)      
  def set_unless_exists(key, value, expires_in = nil)
    key = key.to_s
    expires_in = @options[:expires_in] if expires_in.nil? or expires_in.zero?
    changes = 0
    @conn.acquire do |cache|
      begin
        transaction(:immediate) do
          cache.stmts[:inserter].execute!(key, value, expires_in)
          changes = cache.changes
        end
        capture(:write)
      rescue SQLite3::FullException
        cache.stmts[:extra_pruner].execute!(0.2)
        cache.execute("vacuum")
        retry
      end
    end
    return changes > 0
  end
  
  # get a value by its key
  # if the key doesn't exist or it is expired then null will be returned
  def get(key)
    key = key.to_s
    if record = @conn.acquire{|cache| cache.stmts[:getter].execute!(key)[0] }
      @last_visited[key] = true
      capture(:hit)
      return record[1]
    end
    capture(:miss)
    nil
  end
  
  # delete a key, value pair from the cache
  def delete(key)
    changes = 0
    @conn.aquire do |cache|
      cache.stmts[:deleter].execute!(key)
      changes = cache.changes
    end
    return changes > 0
  end
  
  # increment an integer value by amount, optionally add an expiry value (in seconds)
  def increment(key, amount, expires_in = nil)
    expires_in = @expires_in unless expires_in
    @conn.acquire{|cache| cache.stmts[:incrementer].execute!(key.to_s, amount, expires_in) }
  end
  
  # decrement an integer value by amount, optionally add an expiry value (in seconds)
  def decrement(key, amount, expires_in = nil)
    increment(key, -amount, expires_in)
  end
  
  # delete all entries in the cache up limit (ordered by LRU), if no limit is provided approximately 20% of the entries will be deleted
  def prune(limit=nil)
    @conn.acquire do |cache|
      if limit and limit.is_a? Integer
        cache.stmts[:limited_pruner].execute!(limit)
      elsif limit and limit.is_a? Float
        cache.stmts[:extra_pruner].execute!(limit)
      else
        cache.stmts[:pruner].execute!      
      end
    end
  end
  
  # return the number of key, value pairs in the cache
  def count
    run_stmt(:counter)[0][0]
  end
  
  # return the actual size of the cache file
  def size
    run_stmt(:sizer)[0][0]
  end
  
  # delete all key, value pairs in the cache
  def clear
    run_sql("delete FROM data")
  end
  
  # close the connection to the cache file
  def close
    @running = false
    super
  end
  
  # return the maximum size of the cache
  def max_size
    run_sql("SELECT s.page_size * c.max_page_count FROM pragma_page_size() as s, pragma_max_page_count() as c")[0][0]
  end
  
  # low level access to SQLite transactions, use with caution
  def transaction(mode, acquire=true)
    return cache.transaction(mode){yield} unless acquire
    @conn.acquire do |cache|
      cache.transaction(mode) do
        yield
      end
    end
  end

  private 
  
  def setup
    super # create connection
    @bgthread = spawn_worker # create backgroud pruner thread
  end
  
  def metrics_identifier
    @identifier ||= "#{self.class.name}" # "#{@options[:path]}"
  end
  
  def spawn_worker
    Litesupport.spawn do
      while @running
        @conn.acquire do |cache|
          begin
            cache.transaction(:immediate) do
              @last_visited.delete_if do |k| # there is a race condition here, but not a serious one
                cache.stmts[:toucher].execute!(k) || true
              end
              cache.stmts[:pruner].execute!             
            end
          rescue SQLite3::BusyException
            retry
          rescue SQLite3::FullException
            cache.stmts[:extra_pruner].execute!(0.2)
          rescue Exception
            # database is closed
          end
        end
        sleep @options[:sleep_interval]
      end
    end
  end
  
  def create_connection
    conn = super 
    conn.cache_size = 2000
    conn.journal_size_limit = [(@options[:size]/2).to_i, @options[:min_size]].min
    conn.max_page_count = (@options[:size] / conn.page_size).to_i
    conn.case_sensitive_like = true
    conn.execute("CREATE table if not exists data(id text primary key, value text, expires_in integer, last_used integer)")
    conn.execute("CREATE index if not exists expiry_index on data (expires_in)")
    conn.execute("CREATE index if not exists last_used_index on data (last_used)")
    @sql.each_pair{|k, v| conn.stmts[k] = conn.prepare(v)}
    conn
  end
  
end
