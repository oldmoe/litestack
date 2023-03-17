# frozen_stringe_literal: true

require 'oj'

require_relative './litesupport'

module ActionCable
  module SubscriptionAdapter
    class Litecable < Inline # :nodoc:
      prepend ChannelPrefix

      DEFAULT_OPTIONS = {
        config_path: "./litecable.yml",
        path: "./cable.db",
        sync: 0,
        mmap_size: 16 * 1024 * 1024, # 16MB of memory to easily process 1 year worth of data
        expire_after: 60, # remove messages older than 60 seconds
        listen_interval: 1, # check new messages every second
      }

      def initialize(*)
        super
        @options = DEFAULT_OPTIONS.merge({})
        config = YAML.load_file(@options[:config_path]) rescue {} # an empty hash won't hurt
        config.keys.each do |k| # symbolize keys
          config[k.to_sym] = config[k]
          config.delete k
        end
        @options.merge!(config)
        @options.merge!(options) # make sure options passed to initialize trump everything else
        setup
        
        Litesupport::ForkListener.listen do
          setup
        end
      end

      alias local_broadcast broadcast
      
      def broadcast(channel, payload)
        # send message to the database
        @db.acquire{|db| db.stmts[:publish].execute!(channel.to_s, Oj.dump(payload))}
      end

      def shutdown
        @running = false
        # close connection
      end

      private

      def setup
        @running = true
        @db = Litesupport::Pool.new(1){create_db} # delegate the db creation to the litepool
        @listener = create_listener
        @pruner = create_pruner
        @last_fetched_id = nil
      end

      def create_pruner
        Litesupport.spawn do
          while @running do
            @db.acquire{|db| db.stmts[:pruner].execute!(@options[:expire_after])}
            sleep @options[:expire_after]
          end      
        end
      end

      def create_listener
        Litesupport.spawn do
          while @running do
            listen
            sleep @options[:listen_interval]
          end      
        end
      end
      
      def fetch_last_id
        @db.acquire do |db|
          res = db.get_first_value("SELECT max(id) FROM messages")
          @last_fetched_id = res || 0
        end      
      end

      def listen
        fetch_last_id if @last_fetched_id.nil?
        @db.acquire do |db|
          messages = db.stmts[:fetch].execute!(@last_fetched_id).to_a
          messages.each do |msg|
            @last_fetched_id = msg[0]
            local_broadcast(msg[1], Oj.load(msg[2]))
          end
        end
      end

      def create_db
        db = Litesupport.create_db(@options[:path])
        db.synchronous = @options[:sync]
        db.wal_autocheckpoint = 10000 
        db.mmap_size = @options[:mmap_size]
        db.execute("CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, channel TEXT NOT NULL, value TEXT NOT NULL, created_at INTEGER NOT NULL DEFAULT('unixepoch') ON CONFLICT REPLACE")
        db.execute("CREATE INDEX IF NOT EXISTS messages_by_date ON messages(created_at)")
        db.stmts[:publish] = db.prepare("INSERT INTO messages(channel, value) VALUES ($1, $2)")
        db.stmts[:last_id] = db.prepare("SELECT max(id) FROM messages")
        db.stmts[:fetch] = db.prepare("SELECT id, channel, value,  FROM messages WHERE id > $1")
        db.stmts[:prune] = db.prepare("DELETE FROM messages WHERE CREATED_AD SELECT * FROM messages WHERE created_at < (unixepoch() - $1)")
        db
      end

    
    end
  end
end

