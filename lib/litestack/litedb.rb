# all components should require the support module
require_relative "litesupport"

# all measurable components should require the litemetric class
require_relative "litemetric"

# litedb in particular gets access to litesearch
require_relative "litesearch"

# Litedb inherits from the SQLite3::Database class and adds a few initialization options
class Litedb < ::SQLite3::Database
  # add litemetric support
  include Litemetric::Measurable

  # add litesearch support
  include Litesearch

  # override the original initilaizer to allow for connection configuration
  def initialize(file, options = {}, zfs = nil)
    if block_given?
      super(file, options, zfs) do |db|
        init unless options[:noinit] == true
        yield db
      end
    else
      super(file, options, zfs)
      init unless options[:noinit] == true
    end
    @running = true
    @collecting_metrics = options[:metrics]
    collect_metrics if @collecting_metrics
  end

  def sqlite_version
    SQLite3::SQLITE_VERSION_NUMBER
  end

  def collecting_metrics?
    @collecting_metrics
  end

  # enforce immediate mode to avoid deadlocks for a small performance penalty
  def transaction(mode = :immediate)
    super(mode)
  end

  # return the size of the database file
  def size
    execute("SELECT s.page_size * c.page_count FROM pragma_page_size() AS s, pragma_page_count() AS c")[0][0]
  end

  def schema_object_count(type = nil)
    execute("SELECT count(*) FROM SQLITE_MASTER WHERE iif(?1 IS NOT NULL, type = ?1, TRUE)", type)[0][0]
  end

  # collect snapshot information
  def snapshot
    {
      summary: {
        path: filename,
        journal_mode: journal_mode,
        synchronous: synchronous,
        size: size.to_f / (1024 * 1024),
        tables: schema_object_count("table"),
        indexes: schema_object_count("index")
      }
    }
  end

  # override prepare to return Litedb::Statement (and pass the sql to it)
  def prepare(sql)
    stmt = Litedb::Statement.new(self, sql)
    stmt.sql = sql.strip.upcase
    return stmt unless block_given?
    begin
      yield stmt
    ensure
      stmt.close unless stmt.closed?
    end
  end

  # override execute to capture metrics
  def execute(sql, bind_vars = [], *args, &block)
    if bind_vars.nil? || !args.empty?
      bind_vars = if args.empty?
        []
      else
        [bind_vars] + args
      end
    end

    prepare(sql) do |stmt|
      measure(stmt.stmt_type, stmt.sql) do
        stmt.bind_params(bind_vars)
        stmt = SQLite3::ResultSet.new self, stmt
      end
      if block
        stmt.each do |row|
          yield row
        end
      else
        stmt.to_a
      end
    end
  end

  private

  # default connection configuration values
  def init
    # version 3.37 is required for strict typing support and the newest json operators
    raise Litesupport::Error if SQLite3::SQLITE_VERSION_NUMBER < 3037000
    # time to wait to obtain a write lock before raising an exception
    busy_handler { |i| sleep 0.001 }
    # level of database durability, 2 = "FULL" (sync on every write), other values include 1 = "NORMAL" (sync every 1000 written pages) and 0 = "NONE"
    self.synchronous = 1
    # Journal mode WAL allows for greater concurrency (many readers + one writer)
    self.journal_mode = "WAL"
    # impose a limit on the WAL file to prevent unlimited growth (with a negative impact on read performance as well)
    self.journal_size_limit = 64 * 1024 * 1024
    # set the global memory map so all processes can share data
    self.mmap_size = 128 * 1024 * 1024
    # increase the local connection cache to 2000 pages
    self.cache_size = 2000
  end
end

# the Litedb::Statement also inherits from SQLite3::Statement
class Litedb::Statement < SQLite3::Statement
  include Litemetric::Measurable

  attr_accessor :sql

  def initialize(db, sql)
    super(db, sql)
    collect_metrics if db.collecting_metrics?
  end

  def metrics_identifier
    "Litedb" # overridden to match the parent class
  end

  # return the type of the statement
  def stmt_type
    @stmt_type ||= detect_stmt_type
  end

  def detect_stmt_type
    if @sql.start_with?("SEL", "WITH")
      "Read"
    elsif @sql.start_with?("CRE", "ALT", "DRO")
      "Schema change"
    elsif @sql.start_with?("PRA")
      "Pragma"
    else
      "Write"
    end
  end

  # overriding each to measure the query time (plus the processing time as well, sadly)
  def each
    measure(stmt_type, @sql) do
      super
    end
  end

  # overriding execute to measure the query time
  def execute(*bind_vars)
    res = nil
    measure(stmt_type, @sql) do
      res = super(*bind_vars)
    end
    res
  end
end
