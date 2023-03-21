# frozen_stringe_literal: true

require 'singleton'

require_relative './litesupport'

# this class is a singleton
# and should remain so
class Litemetric

  include Singleton
  include Litesupport::Liteconnection
  
  DEFAULT_OPTIONS = {
    config_path: "./litemetric.yml",
    path: "./metrics.db",
    sync: 1,
    mmap_size: 16 * 1024 * 1024, # 16MB of memory to easily process 1 year worth of data
    flush_interval: 60 # flush data every 1 minute
  }

  def initialize(options = {})
    init(options)
  end
  
  def register(identifier)
    @registered[identifier] = true   
    @metrics[identifier] = {} unless @metrics[identifier]
  end
    
  def capture(id, event, value=nil)
    if event.is_a? Array
      event.each{|e| capture_single_event(id, e, value=nil)}
    else
      capture_single_event(id, event, value=nil)
    end
  end
  
  def capture_single_event(id, event, value=nil)
    hour = current_hour # should that be 5 minutes?
    if @metrics[id][event]
      if @metrics[id][event][hour]
        @metrics[id][event][hour][:count] += 1
        @metrics[id][event][hour][:value] += value unless value.nil?
      else # new hour
        @metrics[id][event][hour] = {count: 1, value: value}
      end
    else # new event
      @metrics[id][event] = {}
      @metrics[id][event][hour] = {count: 1, value: value}
    end
  end

  def ids
    res = run_stmt(:ids_from_summary).to_a
    if res.empty?
      res = run_stmt(:ids_from_events).to_a
    end
    res
  end

  def events(id)
    res = run_stmt(:events_from_summary, id).to_a
    if res.empty?
      res = run_stmt(:events_from_events, id).to_a
    end
    res
  end

  def event(id, name)
    run_stmt(:event_data, id, name).to_a
  end

  private

  def exit_callback
    puts "--- Litemetric detected an exit, flushing metrics"
    @running = false
    flush
  end

  def setup
    super
    @metrics = {}
    @registered = {}
    @flusher = create_flusher
  end

  def current_hour
    (Time.now.to_i / 3600) * 3600
  end
  
  def flush
    to_delete = []
    @conn.acquire do |conn|
      conn.transaction(:immediate) do
        @metrics.each_pair do |id, event_hash|
          event_hash.each_pair do |event, hour_hash|
            hour_hash.each_pair do |hour, data|
              conn.stmts[:upsert].execute!(id, event.to_s, hour, data[:count], data[:value]) if data 
              hour_hash[hour] = nil #{count: 0, value: nil}
              to_delete << [id, event, hour]
            end      
          end      
        end
      end
    end
    to_delete.each do |r| 
      @metrics[r[0]][r[1]].delete(r[2])
      @metrics[r[0]].delete(r[1]) if @metrics[r[0]][r[1]].empty? 
    end
  end
     
  def create_connection
    conn = super
    conn.wal_autocheckpoint = 10000 
    conn.execute("CREATE TABLE IF NOT EXISTS events(id TEXT NOT NULL, name TEXT NOT NULL, count INTEGER DEFAULT(0) NOT NULL ON CONFLICT REPLACE, value INTEGER, created_at INTEGER DEFAULT(strftime('%s', 'now', 'start of hour')) NOT NULL ON CONFLICT REPLACE, PRIMARY KEY(id, name, created_at) ) WITHOUT ROWID")
    conn.execute("CREATE TABLE IF NOT EXISTS events_summary(id TEXT NOT NULL, name TEXT NOT NULL, count INTEGER DEFAULT(0) NOT NULL ON CONFLICT REPLACE, value INTEGER, created_at INTEGER DEFAULT(strftime('%s', 'now', 'start of day')) NOT NULL ON CONFLICT REPLACE, PRIMARY KEY(id, name, created_at) ) WITHOUT ROWID")
    conn.stmts[:report] = conn.prepare("SELECT * FROM events WHERE id = $1 AND name = $2 ORDER BY created_at ASC")
    conn.stmts[:ids_from_summary] = conn.prepare("SELECT id, sum(count) AS count FROM events_summary WHERE created_at >= unixepoch('now', 'start of day', '-7 days') GROUP BY id ORDER BY count")
    conn.stmts[:ids_from_events] = conn.prepare("SELECT id, sum(count) AS count FROM events WHERE created_at >= unixepoch('now', 'start of day', '-7 days') GROUP BY id ORDER BY count")
    conn.stmts[:events_from_summary] = conn.prepare("SELECT name, sum(count) AS count, sum(value) AS sum FROM events_summary WHERE id = $1 AND created_at >= unixepoch('now', 'start of day', '-7 days') GROUP BY id, name ORDER BY count DESC")
    conn.stmts[:events_from_events] = conn.prepare("SELECT name, sum(count) AS count, sum(value) AS sum FROM events WHERE id = $1 AND created_at >= unixepoch('now', 'start of day', '-7 days') GROUP BY id, name ORDER BY count DESC")
    conn.stmts[:event_data] = conn.prepare("SELECT count, value, created_at FROM events WHERE id = $1 AND name = $2 AND created_at >= unixepoch('now', 'start of day', '-7 days') ORDER BY created_at")
    conn.stmts[:upsert] = conn.prepare("INSERT INTO events(id, name, created_at, count, value) VALUES ($1, $2, $3, $4, $5) ON CONFLICT(id, name, created_at) DO UPDATE SET count = count + EXCLUDED.count, value = coalesce(EXCLUDED.value, value, coalesce(value, EXCLUDED.value, value + EXCLUDED.value))")
    conn.stmts[:summarize] = conn.prepare("INSERT INTO events_summary(id, name, created_at, count, value) SELECT id, name, unixepoch(created_at, 'unixepoch', 'start of day') as day, sum(count), sum(value) FROM events WHERE created_at > (SELECT max(created_at) from events_summary) AND created_at < unixepoch('now', 'start of day') GROUP BY id, name, day")
    conn.stmts[:purge_events] = conn.prepare("DELETE FROM events WHERE created_at < unixepoch('now', 'start of day', '-1 year')")
    conn.stmts[:purge_summary] = conn.prepare("DELETE FROM events_summary WHERE created_at < unixepoch('now', 'start of day', '-1 year')")
    conn
  end
  
  def create_flusher
    Litesupport.spawn do
      while @running do
        flush
        sleep @options[:flush_interval]
      end      
    end
  end
       
end

class Litemetric
  module Measurable
            
    def collect_metrics
      @metric = Litemetric.instance
      @metric.register(metrics_identifier)
    end

    def metrics_identifier
      self.class.name # override in included classes
    end

    def capture(event, value=nil)
      return unless @metric
      @metric.capture(metrics_identifier, event, value)
    end
    
    def measure(event)
      return yield unless @metric
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) 
      res = yield
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      value = ( t2 - t1 ) * 1000 # capture time in milliseconds
      capture(event, value)
      res  
    end    
    
    def snapshot
      raise Litestack::NotImplementedError
    end
    
  end
end
