require 'sqlite3'
require 'logger'
require 'oj'
require 'yaml'

module Litesupport

  class Error < StandardError; end
  
  # cache the environment we are running in
  # it is an error to change the environment for a process 
  # or for a child forked from that process
  def self.environment
    @env ||= detect_environment
  end
  
  def self.max_contexts
    return 50 if environment == :fiber || environment == :polyphony
    5    
  end
    
  # identify which environment we are running in
  # we currently support :fiber, :polyphony, :iodine & :threaded
  # in the future we might want to expand to other environments
  def self.detect_environment
    return :fiber if Fiber.scheduler 
    return :polyphony if defined? Polyphony
    return :iodine if defined? Iodine
    return :threaded # fall back for all other environments
  end
  
  # spawn a new execution context
  def self.spawn(&block)
    if self.environment == :fiber
      Fiber.schedule(&block)
    elsif self.environment == :polyphony
      spin(&block)
    elsif self.environment == :threaded or self.environment == :iodine
      Thread.new(&block)
    end
    # we should never reach here
  end
    
  def self.context
    if environment == :fiber || environment == :poylphony
      Fiber.current.storage
    else
      Thread.current
    end
  end
  
  def self.current_context
    if environment == :fiber || environment == :poylphony
      Fiber.current
    else
      Thread.current
    end
  end
  
  # switch the execution context to allow others to run
  def self.switch
    if self.environment == :fiber
      Fiber.scheduler.yield
      true
    elsif self.environment == :polyphony
      Fiber.current.schedule
      Thread.current.switch_fiber
      true
    else
      #Thread.pass
      false
    end   
  end
  
  # mutex initialization
  def self.mutex
    # a single mutex per process (is that ok?)
    @@mutex ||= Mutex.new
  end
  
  # bold assumption, we will only synchronize threaded code
  # if some code explicitly wants to synchronize a fiber
  # they must send (true) as a parameter to this method
  # else it is a no-op for fibers
  def self.synchronize(fiber_sync = false, &block)
    if self.environment == :fiber or self.environment == :polyphony
      yield # do nothing, just run the block as is
    else
      self.mutex.synchronize(&block)
    end
  end
  
  # common db object options
  def self.create_db(path)
    db = SQLite3::Database.new(path)
    db.busy_handler{ switch || sleep(0.0001) }
    db.journal_mode = "WAL"
    db.instance_variable_set(:@stmts, {})
    class << db
      attr_reader :stmts
    end
    db
  end
  
  class Mutex
  
    def initialize
      @mutex = Thread::Mutex.new
    end
    
    def synchronize(&block)
      if Litesupport.environment == :threaded || Litesupport.environment == :iodine
        @mutex.synchronize{ block.call }
      else
        block.call
      end
    end
  
  end
   
  module Forkable
    
    def _fork(*args)
      ppid = Process.pid
      result = super      
      if Process.pid != ppid
        # trigger a restart of all connections owned by Litesupport::Pool
      end
      result
    end
    
  end

  #::Process.singleton_class.prepend(::Litesupport::Forkable)
  
  class Pool
  
    def initialize(count, &block)
      @count = count
      @block = block
      @resources = []
      @mutex = Litesupport::Mutex.new
      @count.times do
        resource = @mutex.synchronize{ block.call }
        @resources << [resource, :free]
      end
    end
    
    def acquire
      # check for pid changes
      acquired = false
      result = nil
      while !acquired do
        @mutex.synchronize do
          if resource = @resources.find{|r| r[1] == :free }
            resource[1] = :busy
            begin
              result = yield resource[0]
            rescue Exception => e
              raise e
            ensure
              resource[1] = :free
              acquired = true
            end
          end
        end
        sleep 0.001 unless acquired
      end
      result
    end
    
  end
     
  module ForkListener
    def self.listeners
      @listeners ||= []
    end
    
    def self.listen(&block)
      listeners << block
    end
  end

  module Forkable
      
    def _fork(*args)
      ppid = Process.pid
      result = super
      if Process.pid != ppid && [:threaded, :iodine].include?(Litesupport.environment)
        ForkListener.listeners.each{|l| l.call }
      end
      result
    end
    
  end
  
  module Liteconnection
    
    include Forkable

    # close, setup, run_stmt and run_sql assume a single connection was created
    def close
      @running = false
      @conn.acquire do |q| 
        q.stmts.each_pair {|k, v| q.stmts[k].close }
        q.close
      end
    end

    private # all methods are private
        
    def init(options = {})
      #c configure the object, loading options from the appropriate location
      configure(options)    
      # setup connections and background threads
      setup      
      # handle process exiting
      at_exit do 
        exit_callback
      end
      # handle forking (restart connections and background threads)
      Litesupport::ForkListener.listen do
        setup
      end
    end  
    
    def configure(options = {})
      # detect environment (production, development, etc.)
      defaults = self.class::DEFAULT_OPTIONS rescue {}
      @options = defaults.merge(options)
      config = YAML.load_file(@options[:config_path]) rescue {} # an empty hash won't hurt
      config.keys.each do |k| # symbolize keys
        config[k.to_sym] = config[k]
        config.delete k
      end
      @options.merge!(config)
      @options.merge!(options) # make sure options passed to initialize trump everything else
    end
    
    def setup
      @conn = create_pooled_connection
      @running = true
    end
    
    def exit_callback
      close
    end

    def run_stmt(stmt, *args)
      @conn.acquire{|q| q.stmts[stmt].execute!(*args) }
    end

    def run_sql(sql, *args)
      @conn.acquire{|q| q.execute(sql, *args) }
    end
    
    def create_pooled_connection(count = 1)
      Litesupport::Pool.new(1){create_connection}  
    end

    # common db object options
    def create_connection
      conn = SQLite3::Database.new(@options[:path])
      conn.busy_handler{ switch || sleep(0.0001) }
      conn.journal_mode = "WAL"
      conn.synchronous = @options[:sync] || 1
      conn.mmap_size = @options[:mmap_size] || 0
      conn.instance_variable_set(:@stmts, {})
      class << conn
        attr_reader :stmts
      end
      conn
    end
    
  end
      
end  

Process.singleton_class.prepend(Litesupport::Forkable)

