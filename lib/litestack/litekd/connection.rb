module Litekd
  class Connection
  
    include Litesupport::Liteconnection
    
    DEFAULT_OPTIONS = {
      path: Litesupport.root.join("kd.sqlite3"),
      sync: 1,
      mmap_size: 16 * 1024 * 1024, # 16MB
    }
    
    def initialize(options = {})
      init(options)
    end

    def create_connection
      conn = super("#{__dir__}/../sql/litekd.sql.yml")
      conn.stmts.keys.each do |stmt|
        self.class.define_method stmt do |*params|
          run_stmt(stmt, *params)
        end
      end
      conn
    end
  end
end
