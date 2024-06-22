# frozen_stringe_literal: true

# all components should require the support module
require_relative "litesupport"
require_relative "litemetric"

require "base64"
require "oj"

class Litecable
  include Litesupport::Liteconnection
  include Litemetric::Measurable

  DEFAULT_OPTIONS = {
    config_path: "./litecable.yml",
    path: Litesupport.root.join("cable.sqlite3"),
    sync: 0,
    mmap_size: 16 * 1024 * 1024, # 16MB
    expire_after: 5, # remove messages older than 5 seconds
    listen_interval: 0.05, # check new messages every 50 milliseconds
    metrics: false
  }

  def initialize(options = {})
    @messages = Litesupport::Pool.new(1) { [] }
    init(options)
    collect_metrics if @options[:metrics]
  end

  # broadcast a message to a specific channel
  def broadcast(channel, payload = nil)
    # group meesages and only do broadcast every 10 ms
    # but broadcast locally normally
    @messages.acquire { |msgs| msgs << [channel.to_s, Oj.dump(payload)] }
    capture(:broadcast, channel)
    local_broadcast(channel, payload)
  end

  # subscribe to a channel, optionally providing a success callback proc
  def subscribe(channel, subscriber, success_callback = nil)
    @subscribers.acquire do |subs|
      subs[channel] = {} unless subs[channel]
      subs[channel][subscriber] = true
    end
    success_callback&.call
    capture(:subscribe, channel)
  end

  # unsubscribe from a channel
  def unsubscribe(channel, subscriber)
    @subscribers.acquire { |subs|
      begin
        subs[channel].delete(subscriber)
      rescue
        nil
      end
    }
    capture(:unsubscribe, channel)
  end

  private

  # broadcast the message to local subscribers
  def local_broadcast(channel, payload = nil)
    subscribers = []
    @subscribers.acquire do |subs|
      break unless subs[channel]
      subscribers = subs[channel].keys
    end
    subscribers.each do |subscriber|
      subscriber.call(payload)
      capture(:message, channel)
    end
  end

  def setup
    super # create connection
    @pid = Process.pid
    @subscribers = Litesupport::Pool.new(1) { {} }
    @running = true
    @listener = create_listener
    @pruner = create_pruner
    @broadcaster = create_broadcaster
    @last_fetched_id = nil
  end

  def create_broadcaster
    Litescheduler.spawn do
      while @running
        @messages.acquire do |msgs|
          if msgs.length > 0
            run_sql("BEGIN IMMEDIATE")
            while (msg = msgs.shift)
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
    Litescheduler.spawn do
      while @running
        run_stmt(:prune, @options[:expire_after])
        sleep @options[:expire_after]
      end
    end
  end

  def create_listener
    Litescheduler.spawn do
      while @running
        @last_fetched_id ||= run_stmt(:last_id)[0][0] || 0
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
    super("#{__dir__}/sql/litecable.sql.yml") do |conn|
      conn.wal_autocheckpoint = 10000
    end
  end
end
