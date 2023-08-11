# frozen_stringe_literal: true

require 'sqlite3'
require 'logger'
require 'oj'
require 'yaml'
require 'pathname'
require 'fileutils'

module Litesupport

  class Error < StandardError; end
  
  def self.max_contexts
    return 50 if scheduler == :fiber || scheduler == :polyphony
    5    
  end

  # Detect the Rack or Rails environment.
  def self.detect_environment
    if defined? Rails
      Rails.env
    elsif ENV["RACK_ENV"]
      ENV["RACK_ENV"]
    elsif ENV["APP_ENV"]
      ENV["APP_ENV"]
    else
      "development"
    end
  end

  def self.environment
    @environment ||= detect_environment
  end

  # cache the scheduler we are running in
  # it is an error to change the scheduler for a process
  # or for a child forked from that process
  def self.scheduler
    @scehduler ||= detect_scheduler
  end

  # identify which scheduler we are running in
  # we currently support :fiber, :polyphony, :iodine & :threaded
  # in the future we might want to expand to other schedulers
  def self.detect_scheduler
    return :fiber if Fiber.scheduler 
    return :polyphony if defined? Polyphony
    return :iodine if defined? Iodine
    return :threaded # fall back for all other schedulers
  end
  
  # spawn a new execution context
  def self.spawn(&block)
    if self.scheduler == :fiber
      Fiber.schedule(&block)
    elsif self.scheduler == :polyphony
      spin(&block)
    elsif self.scheduler == :threaded or self.scheduler == :iodine
      Thread.new(&block)
    end
    # we should never reach here
  end

  def self.context
    if scheduler == :fiber || scheduler == :poylphony
      Fiber.current.storage
    else
      Thread.current
    end
  end
  
  def self.current_context
    if scheduler == :fiber || scheduler == :poylphony
      Fiber.current
    else
      Thread.current
    end
  end
  
  # switch the execution context to allow others to run
  def self.switch
    if self.scheduler == :fiber
      Fiber.scheduler.yield
      true
    elsif self.scheduler == :polyphony
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
  
  # bold assumption, we will only synchronize threaded code!
  # If some code explicitly wants to synchronize a fiber
  # they must send (true) as a parameter to this method
  # else it is a no-op for fibers
  def self.synchronize(fiber_sync = false, &block)
    if self.scheduler == :fiber or self.scheduler == :polyphony
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

  # Databases will be stored by default at this path.
  def self.root
    @root ||= ensure_root_volume detect_root
  end

  # Default path where we'll store all of the databases.
  def self.detect_root
    path = if ENV["LITESTACK_DATA_PATH"]
      ENV["LITESTACK_DATA_PATH"]
    elsif defined? Rails
      "./db"
    else
      "."
    end

    Pathname.new(path).join(Litesupport.environment)
  end

  def self.ensure_root_volume(path)
    FileUtils.mkdir_p path unless path.exist?
    path
  end

  class Mutex
  
    def initialize
      @mutex = Thread::Mutex.new
    end
    
    def synchronize(&block)
      if Litesupport.scheduler == :threaded || Litesupport.scheduler == :iodine
        @mutex.synchronize{ block.call }
      else
        block.call
      end
    end
  
  end
   
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
      if Process.pid != ppid && [:threaded, :iodine].include?(Litesupport.scheduler)
        ForkListener.listeners.each{|l| l.call }
      end
      result
    end
    
  end
  
  module Liteconnection
    
    include Forkable

    # close, setup, run_stmt and run_sql assume a single connection was created
    
    def options
      @options
    end
    
    def close
      @running = false
      @conn.acquire do |q| 
        q.stmts.each_pair {|k, v| q.stmts[k].close }
        q.close
      end
    end

    def size
      run_sql("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")[0][0].to_f / (1024*1024)
    end

    def journal_mode
      run_method(:journal_mode)
    end
    
    def synchronous
      run_method(:synchronous)
    end
    
    def path
      run_method(:filename)
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
      # detect enviornment (production, development, etc.)
      defaults = self.class::DEFAULT_OPTIONS rescue {}
      @options = defaults.merge(options)
      config = YAML.load_file(@options[:config_path]) rescue {} # an empty hash won't hurt
      config = config[Litesupport.environment] if config[Litesupport.environment] # if there is a config for the current enviornment defined then use it, otherwise use the top level declaration
      config.keys.each do |k| # symbolize keys
        config[k.to_sym] = config[k]
        config.delete k
      end
      @options.merge!(config)
      @options.merge!(options) # make sure options passed to initialize trump everything else
    end
    
    def setup
      @conn = create_pooled_connection
      @logger = create_logger
      @running = true
    end
    
    def create_logger
      @options[:logger] = nil unless @options[:logger]
      return @options[:logger] if @options[:logger].respond_to? :info
      return Logger.new(STDOUT) if @options[:logger] == 'STDOUT'
      return Logger.new(STDERR) if @options[:logger] == 'STDERR'
      return Logger.new(@options[:logger]) if @options[:logger].is_a? String 
      return Logger.new(IO::NULL)         
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
    
    def run_method(method, *args)
      @conn.acquire{|q| q.send(method, *args)}
    end

    def run_stmt_method(stmt, method, *args)
      @conn.acquire{|q| q.stmts[stmt].send(method, *args)}
    end

    
    def create_pooled_connection(count = 1)
      Litesupport::Pool.new(1){create_connection}  
    end

    # common db object options
    def create_connection(path_to_sql_file = nil)
      conn = SQLite3::Database.new(@options[:path])
      conn.busy_handler{ Litesupport.switch || sleep(rand * 0.002) }
      conn.journal_mode = "WAL"
      conn.synchronous = @options[:sync] || 1
      conn.mmap_size = @options[:mmap_size] || 0
      conn.instance_variable_set(:@stmts, {})
      class << conn
        attr_reader :stmts
      end
      yield conn if block_given?
      # use the <client>.sql.yml file to define the schema and compile prepared statements
      unless path_to_sql_file.nil?
        sql = YAML.load_file(path_to_sql_file)
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
      end
      conn
    end
        
  end
      
end  

Process.singleton_class.prepend(Litesupport::Forkable)

