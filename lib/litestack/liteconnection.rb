module Litesupport
  module Liteconnection
    include Litescheduler::Forkable

    # close, setup, run_stmt and run_sql assume a single connection was created

    def options
      @options
    end

    def close
      @running = false
      @conn.acquire do |q|
        q.stmts.each_pair { |k, v| q.stmts[k].close }
        q.close
      end
    end

    def size
      run_sql("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")[0][0].to_f / (1024 * 1024)
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

    def transaction(mode = :immediate)
      return yield conn = @checked_out_conn if @checked_out_conn && @checked_out_conn.transaction_active?
      with_connection do |conn|
        if !conn.transaction_active?
          conn.transaction(mode) do
            yield conn
          end
        else
          yield conn
        end
      end
    end

    private # all methods are private

    def init(options = {})
      # c configure the object, loading options from the appropriate location
      configure(options)
      # setup connections and background threads
      setup
      # handle process exiting
      at_exit do
        exit_callback
      end
      # handle forking (restart connections and background threads)
      Litescheduler::ForkListener.listen do
        setup
      end
    end

    def configure(options = {})
      # detect environment (production, development, etc.)
      defaults = begin
        self.class::DEFAULT_OPTIONS
      rescue
        {}
      end
      @options = defaults.merge(options)
      config = begin
        YAML.safe_load(ERB.new(File.read(@options[:config_path])).result)
      rescue
        {}
      end # an empty hash won't hurt
      config = config[Litesupport.environment] if config[Litesupport.environment] # if there is a config for the current environment defined then use it, otherwise use the top level declaration
      config.keys.each do |k| # symbolize keys
        config[k.to_sym] = config[k]
        config.delete k
      end
      @options.merge!(config)
      @options.merge!(options) # make sure options passed to initialize trump everything else
    end

    def setup
      @conn = create_pooled_connection(@options[:connection_count])
      @logger = create_logger
      @running = true
    end

    def create_logger
      @options[:logger] = nil unless @options[:logger]
      return @options[:logger] if @options[:logger].respond_to? :info
      return Logger.new($stdout) if @options[:logger] == "STDOUT"
      return Logger.new($stderr) if @options[:logger] == "STDERR"
      return Logger.new(@options[:logger]) if @options[:logger].is_a? String
      Logger.new(IO::NULL)
    end

    def exit_callback
      close
    end

    def run_stmt(stmt, *args)
      acquire_connection { |conn| conn.stmts[stmt].execute!(*args) }
    end

    def run_sql(sql, *args)
      acquire_connection { |conn| conn.execute(sql, args) }
    end

    def run_method(method, *args)
      acquire_connection { |conn| conn.send(method, *args) }
    end

    def run_stmt_method(stmt, method, *args)
      acquire_connection { |conn| conn.stmts[stmt].send(method, *args) }
    end

    def acquire_connection
      if @checked_out_conn
        yield @checked_out_conn
      else
        @conn.acquire { |conn| yield conn }
      end
    end

    # this will force the other run_* methods to use the
    # checked out connection if one exists
    def with_connection
      @conn.acquire do |conn|
        @checked_out_conn = conn
        yield conn
      ensure
        @checked_out_conn = nil
      end
    end

    def create_pooled_connection(count = 1)
      count = 1 unless count&.is_a?(Integer)
      Litesupport::Pool.new(count) { create_connection }
    end

    # common db object options
    def create_connection(path_to_sql_file = nil)
      conn = SQLite3::Database.new(@options[:path])
      conn.busy_handler { Litescheduler.switch || sleep(rand * 0.002) }
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
                conn.execute(s)
              rescue Exception => e # standard:disable Lint/RescueException
                warn "Error parsing #{k}"
                warn s
                raise e
              end
              conn.user_version = v
            end
          end
        end
        sql["stmts"].each do |k, v|
          conn.stmts[k.to_sym] = conn.prepare(v)
        rescue Exception => e # standard:disable Lint/RescueException
          warn "Error parsing #{k}"
          warn v
          raise e
        end
      end
      conn
    end
  end
end
