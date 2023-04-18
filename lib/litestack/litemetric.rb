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
    flush_interval: 10, # flush data every 1 minute
    summarize_interval: 10 # summarize data every 1 minute
  }

  RESOLUTIONS = {
    minute: 300, # 5 minutes (highest resolution)
    hour: 3600, # 1 hour
    day: 24*3600, # 1 day
    week: 7*24*3600 # 1 week (lowest resolution)
  }

  # :nodoc: 
  def initialize(options = {})
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
    
  def capture(topic, event, key, value=nil)
    if key.is_a? Array
      key.each{|k| capture_single_key(topic, event, k, value)}
    else
      capture_single_key(topic, event, key, value)
    end
  end
  
  def capture_single_key(topic, event, key, value=nil)
    @mutex.synchronize do
      time_slot = current_time_slot # should that be 5 minutes?
      topic_slot = @metrics[topic]
      if event_slot = topic_slot[event]
        if key_slot = event_slot[key]
          if key_slot[time_slot]
            key_slot[time_slot][:count] += 1
            key_slot[time_slot][:value] += value unless value.nil?
          else # new time slot
            key_slot[time_slot] = {count: 1, value: value}
          end
        else
          event_slot[key] = {time_slot => {count: 1, value: value}}
        end
      else # new event
        topic_slot[event] = {key => {time_slot => {count: 1, value: value}}}
      end
    end
  end
  

  ## event reporting
  ##################
  
  def topics
    run_stmt(:list_topics).to_a
  end

  def event_names(resolution, topic)
    run_stmt(:list_event_names, resolution, topic).to_a
  end

  def keys(resolution, topic, event_name)
    run_stmt(:list_event_keys, resolution, topic, event_name).to_a
  end

  def event_data(resolution, topic, event_name, key)
    run_stmt(:list_events_by_key, resolution, topic, event_name, key).to_a
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
    @mutex = Litesupport::Mutex.new
  end

  def current_time_slot
    (Time.now.to_i / 300) * 300 # every 5 minutes 
  end
  
  def flush
    to_delete = []
    @conn.acquire do |conn|
      conn.transaction(:immediate) do
        @metrics.each_pair do |topic, event_hash|
          event_hash.each_pair do |event, key_hash|
            key_hash.each_pair do |key, time_hash|
              time_hash.each_pair do |time, data|
                conn.stmts[:capture_event].execute!(topic, event.to_s, key, time, data[:count], data[:value]) if data 
                time_hash[time] = nil 
                to_delete << [topic, event, key, time]
              end
            end      
          end      
        end
      end
    end
    to_delete.each do |r| 
      @metrics[r[0]][r[1]][r[2]].delete(r[3])
      @metrics[r[0]][r[1]].delete(r[2]) if @metrics[r[0]][r[1]][r[2]].empty? 
      @metrics[r[0]].delete(r[1]) if @metrics[r[0]][r[1]].empty? 
    end
  end  
     
  def create_connection
    conn = super
    conn.wal_autocheckpoint = 10000
    sql = YAML.load_file("#{__dir__}/litemetric.sql.yml")
    version = sql["version"].to_f
    sql["schema"].each { |k, v| conn.execute(v) }
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
    end

    def metrics_identifier
      self.class.name # override in included classes
    end

    def capture(event, key, value=nil)
      return unless @litemetric
      @litemetric.capture(metrics_identifier, event, key, value)
    end
    
    def measure(event, key)
      return yield unless @litemetric
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) 
      res = yield
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      value = (( t2 - t1 ) * 1000).round # capture time in milliseconds
      capture(event, key, value)
      res  
    end    
    
    def snapshot
      raise Litestack::NotImplementedError
    end
    
  end
end
