# frozen_stringe_literal: true

# all components should require the support module
require_relative 'litesupport'

##
#Litequeue is a simple queueing system for Ruby applications that allows you to push and pop values from a queue. It provides a straightforward API for creating and managing named queues, and for adding and removing values from those queues. Additionally, it offers options for scheduling pops at a certain time in the future, which can be useful for delaying processing until a later time.
#
#Litequeue is built on top of SQLite, which makes it very fast and efficient, even when handling large volumes of data. This lightweight and easy-to-use queueing system serves as a good foundation for building more advanced job processing frameworks that require basic queuing capabilities.
#
  
class Litequeue

  # the default options for the queue
  # can be overriden by passing new options in a hash 
  # to Litequeue.new
  #   path: "./queue.db"
  #   mmap_size: 128 * 1024 * 1024 -> 128MB to be held in memory
  #   sync: 1 -> sync only when checkpointing
  
  DEFAULT_OPTIONS = {
    path: "./queue.db",
    mmap_size: 32 * 1024,
    sync: 1
  }

  # create a new instance of the litequeue object
  # accepts an optional options hash which will be merged with the DEFAULT_OPTIONS
  #   queue = Litequeue.new
  #   queue.push("somevalue", 2) # the value will be ready to pop in 2 seconds
  #   queue.pop # => nil
  #   sleep 2
  #   queue.pop # => "somevalue"
  
  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)
    @queue = Litesupport::Pool.new(1){create_db} # delegate the db creation to the litepool
  end
   
  # push an item to the queue, optionally specifying the queue name (defaults to default) and after how many seconds it should be ready to pop (defaults to zero)
  # a unique job id is returned from this method, can be used later to delete it before it fires. You can push string, integer, float, true, false or nil values
  #
  def push(value, delay=0, queue='default')
    # @todo - check if queue is busy, back off if it is
    # also bring back the synchronize block, to prevent
    # a race condition if a thread hits the busy handler
    # before the current thread proceeds after a backoff
    result = run_stmt(:push, queue, delay, value)[0]
    return result[0] if result
  end
  
  alias_method :"<<", :push
  
  # pop an item from the queue, optionally with a specific queue name (default queue name is 'default')
  def pop(queue='default', limit = 1)
   res = run_stmt(:pop, queue, limit)
   return res[0] if res.length == 1
   return nil if res.empty?
   res
  end
  
  # delete an item from the queue
  #   queue = Litequeue.new
  #   id = queue.push("somevalue")
  #   queue.delete(id) # => "somevalue"
  #   queue.pop # => nil
  def delete(id, queue='default')
    fire_at, id = id.split("-")
    result = run_stmt(:delete, queue, fire_at.to_i, id)[0]  
  end
  
  # deletes all the entries in all queues, or if a queue name is given, deletes all entries in that specific queue
  def clear(queue=nil)
    run_sql("DELETE FROM _ul_queue_ WHERE iif(?, queue = ?,  1)", queue)
  end

  # returns a count of entries in all queues, or if a queue name is given, reutrns the count of entries in that queue
  def count(queue=nil)
    run_sql("SELECT count(*) FROM _ul_queue_ WHERE iif(?, queue = ?, 1)", queue)[0][0]
  end
  
  # return the size of the queue file on disk
  def size
    run_sql("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")[0][0] 
  end
  
  def queues_info
    run_sql("SELECT queue, count(*) AS count, avg(unixepoch() - created_at), min(unixepoch() - created_at), max(unixepoch() - created_at) FROM _ul_queue_ GROUP BY queue ORDER BY count DESC ")
  end
  
  def info
    counts = {}
    queues_info.each do |qc|
      counts[qc[0]] = {count: qc[1], time_in_queue: {avg: qc[2], min: qc[3], max: qc[4]}}
    end
    {size: size, count: count, info: counts}
  end
  
  def close
    @queue.acquire do |q| 
      q.stmts.each_pair {|k, v| q.stmts[k].close }
      q.close
    end
  end

  private  
  
  def run_stmt(stmt, *args)
    @queue.acquire{|q| q.stmts[stmt].execute!(*args) }
  end

  def run_sql(sql, *args)
    @queue.acquire{|q| q.execute(sql, *args) }
  end
    
  def create_db
    db = Litesupport.create_db(@options[:path])
    db.synchronous = @options[:sync]
    db.wal_autocheckpoint = 10000 
    db.mmap_size = @options[:mmap_size]
    db.execute("CREATE TABLE IF NOT EXISTS _ul_queue_(queue TEXT DEFAULT('default') NOT NULL ON CONFLICT REPLACE, fire_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, id TEXT DEFAULT(CAST((strftime('%f') * 1000) AS INTEGER) || hex(randomblob(8))) NOT NULL ON CONFLICT REPLACE, value TEXT, created_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, PRIMARY KEY(queue, fire_at ASC, id) ) WITHOUT ROWID")
    db.stmts[:push] = db.prepare("INSERT INTO _ul_queue_(queue, fire_at, value) VALUES ($1, (strftime('%s') + $2), $3) RETURNING fire_at || '-' || id")
    db.stmts[:pop] = db.prepare("DELETE FROM _ul_queue_ WHERE (queue, fire_at, id) IN (SELECT queue, fire_at, id FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at <= (unixepoch()) ORDER BY fire_at ASC LIMIT ifnull($2, 1)) RETURNING fire_at || '-' || id, value")
    db.stmts[:delete] = db.prepare("DELETE FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at = $2 AND id = $3 RETURNING value")
    db
  end

end  
