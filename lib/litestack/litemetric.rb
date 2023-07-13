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
    mmap_size: 128 * 1024 * 1024, # 16MB of memory to easily process 1 year worth of data
    flush_interval:  10, # flush data every 10 seconds
    summarize_interval: 30, # summarize data every 1/2 minute
    snapshot_interval: 10*60 # snapshot every 10 minutes
  }

  RESOLUTIONS = {
    minute: 300, # 5 minutes (highest resolution)
    hour: 3600, # 1 hour
    day: 24*3600, # 1 day
    week: 7*24*3600 # 1 week (lowest resolution)
  }

  # :nodoc:
  def self.options=(options)
    # an ugly hack to pass options to a singleton
    # need to rethink the whole singleton thing
    @options = options
  end
  
  def self.options
    @options
  end

  # :nodoc: 
  def initialize(options = {})
    options = options.merge(Litemetric.options) if Litemetric.options
    init(options)
  end
  
  # registers a class for metrics to be collected
  def register(identifier)
    @registered[identifier] = true   
    @metrics[identifier] = {} unless @metrics[identifier]
    run_stmt(:register_topic, identifier) # it is safe to call register topic multiple times with the same identifier
  end
  
  ## event capturing
  ##################
  
  
  def capture(topic, event, key=event, value=nil)
    @collector.capture(topic, event, key, value)
  end
      
  def capture_snapshot(topic, state)
    run_stmt(:capture_state, topic, Oj.dump(state))
  end

  ## event reporting
  ##################
  
  def topics
    run_stmt(:list_topics).to_a
  end
  
  def topic_summaries(resolution, count, order, dir, search)
    search = "%#{search}%" if search
    if dir.downcase == "desc" 
      run_stmt(:topics_summaries, resolution, count, order, search).to_a
    else
      run_stmt(:topics_summaries_asc, resolution, count, order, search).to_a
    end
  end
    
  def events_summaries(topic, resolution, order, dir, search, count)
    search = "%#{search}%" if search
    if dir.downcase == "desc" 
      run_stmt(:events_summaries, topic, resolution, order, search, count).to_a
    else
      run_stmt(:events_summaries_asc, topic, resolution, order, search, count).to_a
    end
  end
  
  def keys_summaries(topic, event, resolution, order, dir, search, count)
    search = "%#{search}%" if search
    if dir.downcase == "desc" 
      run_stmt(:keys_summaries, topic, event, resolution, order, search, count).to_a
    else
      run_stmt(:keys_summaries_asc, topic, event, resolution, order, search, count).to_a
    end 
  end

  def topic_data_points(step, count, resolution, topic)
    run_stmt(:topic_data_points, step, count, resolution, topic).to_a
  end 

  def event_data_points(step, count, resolution, topic, event)
    run_stmt(:event_data_points, step, count, resolution, topic, event).to_a
  end 

  def key_data_points(step, count, resolution, topic, event, key)
    run_stmt(:key_data_points, step, count, resolution, topic, event, key).to_a
  end 

  def snapshot(topic)
    run_stmt(:snapshot, topic)[0].to_a
  end
  
  ## summarize data
  #################  

  def summarize
    run_stmt(:summarize_events, RESOLUTIONS[:hour], "hour", "minute") 
    run_stmt(:summarize_events, RESOLUTIONS[:day], "day", "hour") 
    run_stmt(:summarize_events, RESOLUTIONS[:week], "week", "day")
    run_stmt(:delete_events, "minute", RESOLUTIONS[:hour]*1) 
    run_stmt(:delete_events, "hour", RESOLUTIONS[:day]*1) 
    run_stmt(:delete_events, "day", RESOLUTIONS[:week]*1) 
  end

  ## background stuff
  ###################

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
    @summarizer = create_summarizer
    @collector = Litemetric::Collector.new({dbpath: @options[:path]})
    @mutex = Litesupport::Mutex.new
  end

  def current_time_slot
    (Time.now.to_i / 300) * 300 # every 5 minutes 
  end
  
  def flush
    @collector.flush
  end
     
  def create_connection
    conn = super
    conn.wal_autocheckpoint = 10000
    sql = YAML.load_file("#{__dir__}/litemetric.sql.yml")
    version = conn.get_first_value("PRAGMA user_version")
    sql["schema"].each_pair do |v, obj| 
      if v > version
        conn.transaction do 
          obj.each{|k, s| conn.execute(s)}
          conn.user_version = v
        end
      end
    end 
    sql["stmts"].each { |k, v| conn.stmts[k.to_sym] = conn.prepare(v) }
    conn
  end
  
  def create_flusher
    Litesupport.spawn do
      while @running do
        sleep @options[:flush_interval]
        @mutex.synchronize do
          flush
        end
      end      
    end 
  end
  
  def create_summarizer
    Litesupport.spawn do
      while @running do
        sleep @options[:summarize_interval]
        summarize
      end      
    end 
  end
       
end

## Measurable Module
####################

class Litemetric
  module Measurable
            
    def collect_metrics
      @litemetric = Litemetric.instance
      @litemetric.register(metrics_identifier)
      @snapshotter = create_snapshotter      
    end

    def create_snapshotter
      Litesupport.spawn do
        while @running do
          sleep @litemetric.options[:snapshot_interval]
          capture_snapshot
        end      
      end 
    end

    def metrics_identifier
      self.class.name # override in included classes
    end

    def capture(event, key=event, value=nil)
      return unless @litemetric
      @litemetric.capture(metrics_identifier, event, key, value)
    end
    
    def measure(event, key=event)
      return yield unless @litemetric
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) 
      res = yield
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      value = (( t2 - t1 ) * 1000).round # capture time in milliseconds
      capture(event, key, value)
      res  
    end    
    
    def capture_snapshot
      return unless @litemetric
      state = snapshot if defined? snapshot
      if state
        @litemetric.capture_snapshot(metrics_identifier, state)
      end
    end
        
  end
end

class Litemetric

  class Collector

    include Litesupport::Liteconnection
    
    DEFAULT_OPTIONS = {
      path: ":memory:",
      sync: 1,
      flush_interval:  3, # flush data every 1 minute
      summarize_interval: 10, # summarize data every 1 minute
      snapshot_interval: 1 # snapshot every 10 minutes
    }

    RESOLUTIONS = {
      minute: 300, # 5 minutes (highest resolution)
      hour: 3600, # 1 hour
      day: 24*3600, # 1 day
      week: 7*24*3600 # 1 week (lowest resolution)
    }
    
    def initialize(options = {})
      init(options)
    end
    
    def capture(topic, event, key, value=nil)
      if key.is_a? Array
        key.each{|k| capture_single_key(topic, event, k, value)}
      else
        capture_single_key(topic, event, key, value)
      end
    end
        
    def capture_single_key(topic, event, key, value)
      run_stmt(:capture_event, topic.to_s, event.to_s, key.to_s, nil ,1, value)
    end
    
    def flush
      t = Time.now
      limit = 1000
      count = run_stmt(:event_count)[0][0]
      while count > 0
        @conn.acquire do |conn|
          conn.transaction(:immediate) do
            conn.stmts[:migrate_events].execute!(limit)
            conn.stmts[:delete_migrated_events].execute!(limit)
            count = conn.stmts[:event_count].execute![0][0]
          end         
        end
        sleep 0.005
      end
    end

    def create_connection
      conn = super
      conn.execute("ATTACH ? as m", @options[:dbpath])
      conn.wal_autocheckpoint = 10000
      sql = YAML.load_file("#{__dir__}/litemetric_collector.sql.yml")
      version = conn.get_first_value("PRAGMA user_version")
      sql["schema"].each_pair do |v, obj| 
        if v > version
          conn.transaction do 
            obj.each do |k, s| 
              begin
                conn.execute(s)
              rescue Exception => e
                STDERR.puts "Error parsing #{k}"
                STDERR.puts s
                raise e
              end
            end
            conn.user_version = v
          end
        end
      end 
      sql["stmts"].each do |k, v| 
        begin
          conn.stmts[k.to_sym] = conn.prepare(v) 
        rescue Exception => e
          STDERR.puts "Error parsing #{k}"
          STDERR.puts v
          raise e
        end
      end
      conn
    end
    
  end
  
end
