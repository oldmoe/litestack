# all components should require the support module
require_relative 'litesupport'

# Litedb inherits from the SQLite3::Database class and adds a few initialization options
module Litedb
  module Statement
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
      if @sql.start_with?("SEL") || @sql.start_with?("WITH")
        "Read"
      elsif @sql.start_with?("CRE") || @sql.start_with?("ALT") || @sql.start_with?("DRO")
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

  # add litemetric support
  include Litemetric::Measurable
  
  # overrride the original initializer to allow for connection configuration
  def initialize(file, options = {}, zfs = nil )
    @running = true
    @collecting_metrics = options[:metrics]
    collect_metrics if @collecting_metrics
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
    execute("SELECT s.page_size * c.page_count FROM pragma_page_size() as s, pragma_page_count() as c")[0][0]
  end
  
  # collect snapshot information
  def snapshot
    {
      summary: {
        path: filename,
        journal_mode: journal_mode,
        synchronous: synchronous,
        size: size
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
      if args.empty?
        bind_vars = []
      else
        bind_vars = [bind_vars] + args
      end
    end
    
    prepare(sql) do |stmt|
      measure(stmt.stmt_type, stmt.sql) do
        stmt.bind_params(bind_vars)
        stmt = SQLite3::ResultSet.new self, stmt
      end
      if block_given?
        stmt.each do |row|
          yield row
        end
      else
        stmt.to_a
      end
    end  
   
  end
end
