# frozen_stringe_literal: true
require 'ultralite'

module Ultralite
	
	class Queue

		DEFAULT_PATH = "./ultralite.queue"
	  
	  def initialize(options = {})
			@path = options[:path] || DEFAULT_PATH
			@queue = create_db(@path)
			prepare
	  end
	  
	  def create_db(path)
	    db = SQLite3::Database.new(path)
	    db.journal_mode = "WAL"
	    db.synchronous = 1
	    db.busy_handler{|i| sleep 0.0001}
	    db.wal_autocheckpoint = 10000
	    db.execute("CREATE TABLE IF NOT EXISTS _ul_queue_(queue TEXT DEFAULT('default') NOT NULL ON CONFLICT REPLACE, fire_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, id TEXT DEFAULT(hex(randomblob(4))) NOT NULL ON CONFLICT REPLACE, value TEXT, created_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, PRIMARY KEY(queue, fire_at ASC, id) ) WITHOUT ROWID")
	    db
	  end

    def prepare
      @push = @queue.prepare("INSERT INTO _ul_queue_(queue, fire_at, value) VALUES ($1, (strftime('%s') + $2) * 100000 + CAST(strftime('%f') * 1000 AS INTEGER), $3) RETURNING fire_at, id")
      @pop = @queue.prepare("DELETE FROM _ul_queue_ WHERE (queue, fire_at, id) = (SELECT queue, min(fire_at), id FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at <= (unixepoch() + 1) * 100000 limit 1) RETURNING fire_at, id, value")
      @deleter = @queue.prepare("DELETE FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at = $2 AND id = $3 RETURNING value")
    end
    
    def push(value, delay=0, queue='default')
      result = @push.execute!(queue, delay, value)[0]
      return "#{result[0]}-#{result[1]}" if result
    end
    
    def pop(queue='default')
      result = @pop.execute!(queue)[0]
      return ["#{result[0]}-#{result[1]}", result[2]] if result
    end
    
    def delete(id, queue='default')
      fire_at, id = id.split("_")
      result = @deleter.execute!(queue, fire_at.to_i, id)[0]
    end
    
     def clear
      @queue.execute("DELETE FROM _ul_queue_")
    end

    def count
      @queue.get_first_value("SELECT count(*) FROM _ul_queue_")
    end
    
    def size
      @queue.get_first_value("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")
    end
	end	# class Queue
	
end # module Ultralite



