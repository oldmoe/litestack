# frozen_stringe_literal: true

# all components should require the support module
require_relative "litesupport"
require_relative "litemetric"

##
# Litecache is a caching library for Ruby applications that is built on top of SQLite. It is designed to be simple to use, very fast, and feature-rich, providing developers with a reliable and efficient way to cache data.
#
# One of the main features of Litecache is automatic key expiry, which allows developers to set an expiration time for each cached item. This ensures that cached data is automatically removed from the cache after a certain amount of time has passed, reducing the risk of stale data being served to users.
#
# In addition, Litecache supports LRU (Least Recently Used) removal, which means that if the cache reaches its capacity limit, the least recently used items will be removed first to make room for new items. This ensures that the most frequently accessed data is always available in the cache.
#
# Litecache also supports integer value increment/decrement, which allows developers to increment or decrement the value of a cached item in a thread-safe manner. This is useful for implementing counters or other types of numerical data that need to be updated frequently.
#
# Overall, Litecache is a powerful and flexible caching library that provides automatic key expiry, LRU removal, and integer value increment/decrement capabilities. Its fast performance and simple API make it an excellent choice for Ruby applications that need a reliable and efficient way to cache data.

class Litecache
  include Litesupport::Liteconnection
  include Litemetric::Measurable

  # the default options for the cache
  # can be overridden by passing new options in a hash
  # to Litecache.new
  #   path: "./cache.db"
  #   expiry: 60 * 60 * 24 * 30 -> one month default expiry if none is provided
  #   size: 128 * 1024 * 1024 -> 128MB
  #   mmap_size: 128 * 1024 * 1024 -> 128MB to be held in memory
  #   min_size: 32 * 1024 -> 32KB
  #   return_full_record: false -> only return the payload
  #   sleep_interval: 1 -> 1 second of sleep between cleanup runs

  DEFAULT_OPTIONS = {
    path: Litesupport.root.join("cache.sqlite3"),
    config_path: "./litecache.yml",
    sync: 0,
    expiry: 60 * 60 * 24 * 30, # one month
    size: 128 * 1024 * 1024, # 128MB
    mmap_size: 128 * 1024 * 1024, # 128MB
    min_size: 8 * 1024 * 1024, # 16MB
    return_full_record: false, # only return the payload
    sleep_interval: 30, # 30 seconds
    metrics: false
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
    options[:size] = DEFAULT_OPTIONS[:min_size] if options[:size] && options[:size] < DEFAULT_OPTIONS[:min_size]
    init(options)
    @expires_in = @options[:expiry] || 60 * 60 * 24 * 30
    collect_metrics if @options[:metrics]
  end

  # add a key, value pair to the cache, with an optional expiry value (number of seconds)
  def set(key, value, expires_in = nil)
    key = key.to_s
    expires_in ||= @expires_in
    begin
      run_stmt(:setter, key, value, expires_in)
      capture(:set, key)
    rescue SQLite3::FullException
      run_stmt(:extra_pruner, 0.2)
      run_sql("vacuum")
      retry
    end
    true
  end

  # set multiple keys and values in one shot set_multi({k1: v1, k2: v2, ... })
  def set_multi(keys_and_values, expires_in = nil)
    expires_in ||= @expires_in
    transaction do |conn|
      keys_and_values.each_pair do |k, v|
        key = k.to_s
        run_stmt(:setter, key, v, expires_in)
        capture(:set, key)
      rescue SQLite3::FullException
        run_stmt(:extra_pruner, 0.2)
        run_sql("vacuum")
        retry
      end
    end
    true
  end

  # add a key, value pair to the cache, but only if the key doesn't exist, with an optional expiry value (number of seconds)
  def set_unless_exists(key, value, expires_in = nil)
    key = key.to_s
    expires_in ||= @expires_in
    changes = 0
    @conn.acquire do |cache|
      cache.transaction(:immediate) do
        cache.stmts[:inserter].execute!(key, value, expires_in)
        changes = cache.changes
      end
      capture(:set, key)
    rescue SQLite3::FullException
      cache.stmts[:extra_pruner].execute!(0.2)
      cache.execute("vacuum")
      retry
    end
    changes > 0
  end

  # get a value by its key
  # if the key doesn't exist or it is expired then null will be returned
  def get(key)
    key = key.to_s
    if (record = run_stmt(:getter, key)[0])
      capture(:get, key, 1)
      return record[1]
    end
    capture(:get, key, 0)
    nil
  end

  # get multiple values by their keys, a hash with values corresponding to the keys
  # is returned,
  def get_multi(*keys)
    results = {}
    transaction(:deferred) do |conn|
      keys.length.times do |i|
        key = keys[i].to_s
        if (record = run_stmt(:getter, key)[0])
          results[keys[i]] = record[1] # use the original key format
          capture(:get, key, 1)
        else
          capture(:get, key, 0)
        end
      end
    end
    results
  end

  # delete a key, value pair from the cache
  def delete(key)
    changes = 0
    @conn.acquire do |cache|
      cache.stmts[:deleter].execute!(key)
      changes = cache.changes
    end
    changes > 0
  end

  # increment an integer value by amount, optionally add an expiry value (in seconds)
  def increment(key, amount = 1, expires_in = nil)
    expires_in ||= @expires_in
    @conn.acquire { |cache| cache.stmts[:incrementer].execute!(key.to_s, amount, expires_in)[0][0] }
  end

  # decrement an integer value by amount, optionally add an expiry value (in seconds)
  def decrement(key, amount = 1, expires_in = nil)
    increment(key, -amount, expires_in)
  end

  # delete all entries in the cache up limit (ordered by LRU), if no limit is provided approximately 20% of the entries will be deleted
  def prune(limit = nil)
    @conn.acquire do |cache|
      if limit&.is_a? Integer
        cache.stmts[:limited_pruner].execute!(limit)
      elsif limit&.is_a? Float
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
  # def size
  #  run_stmt(:sizer)[0][0]
  # end

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
    run_sql("SELECT s.page_size * c.max_page_count FROM pragma_page_size() as s, pragma_max_page_count() as c")[0][0].to_f / (1024 * 1024)
  end

  def snapshot
    {
      summary: {
        path: path,
        journal_mode: journal_mode,
        synchronous: synchronous,
        size: size,
        max_size: max_size,
        entries: count
      }
    }
  end

  private

  def setup
    super # create connection
    @bgthread = spawn_worker # create background pruner thread
  end

  def spawn_worker
    Litescheduler.spawn do
      while @running
        @conn.acquire do |cache|
          cache.stmts[:pruner].execute!
        rescue SQLite3::BusyException
          retry
        rescue SQLite3::FullException
          cache.stmts[:extra_pruner].execute!(0.2)
        rescue Exception # standard:disable Lint/RescueException
          # database is closed
        end
        sleep @options[:sleep_interval]
      end
    end
  end

  def create_connection
    super("#{__dir__}/sql/litecache.sql.yml") do |conn|
      conn.cache_size = 2000
      conn.journal_size_limit = [(@options[:size] / 2).to_i, @options[:min_size]].min
      conn.max_page_count = (@options[:size] / conn.page_size).to_i
      conn.case_sensitive_like = true
    end
  end
end
