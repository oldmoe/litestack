# frozen_stringe_literal: true

# all components should require the support module
require_relative 'litesupport'
require_relative 'litemetric'

require 'base64'
require 'oj'

class Litecable

  include Litesupport::Liteconnection
  include Litemetric::Measurable


  DEFAULT_OPTIONS = {
    config_path: "./litecable.yml",
    path: "./cable.db",
    sync: 0,
    mmap_size: 16 * 1024 * 1024, # 16MB
    expire_after: 5, # remove messages older than 5 seconds
    listen_interval: 0.05, # check new messages every 50 milliseconds
    metrics: false
  }
  
  def initialize(options = {})  
    init(options)
    @messages = []
  end
  
  # broadcast a message to a specific channel
  def broadcast(channel, payload=nil)
    # group meesages and only do broadcast every 10 ms
    #run_stmt(:publish, channel.to_s, Oj.dump(payload), @pid)
    # but broadcast locally normally
    @mutex.synchronize{ @messages << [channel.to_s, Oj.dump(payload)] }
    local_broadcast(channel, payload) 
  end
  
  # subscribe to a channel, optionally providing a success callback proc
  def subscribe(channel, subscriber, success_callback = nil)
    @mutex.synchronize do
      @subscribers[channel] = {} unless @subscribers[channel]
      @subscribers[channel][subscriber] = true
    end
  end
  
  # unsubscribe from a channel
  def unsubscribe(channel, subscriber)
    @mutex.synchronize do
      @subscribers[channel].delete(subscriber) rescue nil
    end
  end

  private 
    
  def local_broadcast(channel, payload=nil)
    return unless @subscribers[channel]
    subscribers = []
    @mutex.synchronize do
      subscribers = @subscribers[channel].keys
    end
    subscribers.each do |subscriber|
      subscriber.call(payload)      
    end
  end  
      
  def setup
    super # create connection
    @pid = Process.pid
    @subscribers = {}
    @mutex = Litesupport::Mutex.new
    @running = true
    @listener = create_listener
    @pruner = create_pruner
    @broadcaster = create_broadcaster
    @last_fetched_id = nil
  end

  def create_broadcaster
    Litesupport.spawn do
      while @running do
        @mutex.synchronize do
          if @messages.length > 0
            run_sql("BEGIN IMMEDIATE")
            while msg = @messages.shift
              run_stmt(:publish, msg[0], msg[1], @pid)
            end
            run_sql("END")
          end
        end
        sleep 0.02
      end      
    end
  end

  def create_pruner
    Litesupport.spawn do
      while @running do
        run_stmt(:prune, @options[:expire_after])
        sleep @options[:expire_after]
      end      
    end
  end

  def create_listener
    Litesupport.spawn do
      while @running do
        @last_fetched_id ||= (run_stmt(:last_id)[0][0] || 0)
        @logger.info @last_fetched_id
        run_stmt(:fetch, @last_fetched_id, @pid).to_a.each do |msg|
          @logger.info "RECEIVED #{msg}"
          @last_fetched_id = msg[0]
          local_broadcast(msg[1], Oj.load(msg[2])) 
        end
        sleep @options[:listen_interval]
      end      
    end
  end

  def create_connection
    conn = super
    conn.wal_autocheckpoint = 10000 
    sql = YAML.load_file("#{__dir__}/litecable.sql.yml")
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
  
end
