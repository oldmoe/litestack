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
    mmap_size: 16 * 1024 * 1024, # 16MB of memory to easily process 1 year worth of data
    expire_after: 5, # remove messages older than 5 seconds
    listen_interval: 0.01, # check new messages every 10 milliseconds
    metrics: false
  }
  
  def initialize(options = {})  
    init(options)
  end

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
  
  def broadcast(channel, payload=nil)
    run_stmt(:publish, channel.to_s, Oj.dump(payload), @pid)
    local_broadcast(channel, payload) 
  end
  
  def subscribe(channel, subscriber, success_callback = nil)
    @mutex.synchronize do
      @subscribers[channel] = {} unless @subscribers[channel]
      @subscribers[channel][subscriber] = true
    end
  end
  
  def unsubscribe(channel, subscriber)
    @mutex.synchronize do
      @subscribers[channel].delete(subscriber) rescue nil
    end
  end

  private 
    
  def setup
    super # create connection
    @pid = Process.pid
    @subscribers = {}
    @mutex = Litesupport::Mutex.new
    @running = true
    @listener = create_listener
    @pruner = create_pruner
    @last_fetched_id = nil
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
        @last_fetched_id ||= (run_sql("SELECT max(id) FROM messages")[0][0] || 0)
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
    conn.execute("CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY autoincrement, channel TEXT NOT NULL, value TEXT NOT NULL, pid INTEGER, created_at INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT(unixepoch()))")
    conn.execute("CREATE INDEX IF NOT EXISTS messages_by_date ON messages(created_at)")
    conn.stmts[:publish] = conn.prepare("INSERT INTO messages(channel, value, pid) VALUES ($1, $2, $3)")
    conn.stmts[:last_id] = conn.prepare("SELECT max(id) FROM messages")
    conn.stmts[:fetch] = conn.prepare("SELECT id, channel, value FROM messages WHERE id > $1 and pid != $2")
    conn.stmts[:prune] = conn.prepare("DELETE FROM messages WHERE created_at < (unixepoch() - $1)")
    conn.stmts[:check_prune] = conn.prepare("SELECT count(*) FROM messages WHERE created_at < (unixepoch() - $1)")
    conn
  end
  
end
