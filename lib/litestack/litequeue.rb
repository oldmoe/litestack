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
    @queue = create_db #(@options[:path])
    prepare
  end
   
  # push an item to the queue, optionally specifying the queue name (defaults to default) and after how many seconds it should be ready to pop (defaults to zero)
  # a unique job id is returned from this method, can be used later to delete it before it fires. You can push string, integer, float, true, false or nil values
  #
  def push(value, delay=0, queue='default')
    result = @push.execute!(queue, delay, value)[0]
    return result[0] if result
  end
  
  alias_method :"<<", :push
  
  # pop an item from the queue, optionally with a specific queue name (default queue name is 'default')
  def pop(queue='default')
    result = nil
    Litesupport.synchronize do
      result = @pop.execute!(queue)[0]
    end
    result 
  end
  
  # delete an item from the queue
  #   queue = Litequeue.new
  #   id = queue.push("somevalue")
  #   queue.delete(id) # => "somevalue"
  #   queue.pop # => nil
  def delete(id, queue='default')
    fire_at, id = id.split("_")
    result = @deleter.execute!(queue, fire_at.to_i, id)[0]
  end
  
  # deletes all the entries in all queues, or if a queue name is given, deletes all entries in that specific queue
  def clear(queue=nil)
    @queue.execute("DELETE FROM _ul_queue_ WHERE iif(?, queue = ?,  1)", queue)
  end

  # returns a count of entries in all queues, or if a queue name is given, reutrns the count of entries in that queue
  def count(queue=nil)
    @queue.get_first_value("SELECT count(*) FROM _ul_queue_ WHERE iif(?, queue = ?, 1)", queue)
  end
  
  # return the size of the queue file on disk
  def size
    @queue.get_first_value("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")
  end

  private  
  
  def create_db
    db = Litesupport.create_db(@options[:path])
    db.synchronous = @options[:sync]
    db.wal_autocheckpoint = 10000 
    db.mmap_size = @options[:mmap_size]
    db.execute("CREATE TABLE IF NOT EXISTS _ul_queue_(queue TEXT DEFAULT('default') NOT NULL ON CONFLICT REPLACE, fire_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, id TEXT DEFAULT(hex(randomblob(8)) || (strftime('%f') * 100)) NOT NULL ON CONFLICT REPLACE, value TEXT, created_at INTEGER DEFAULT(unixepoch()) NOT NULL ON CONFLICT REPLACE, PRIMARY KEY(queue, fire_at ASC, id) ) WITHOUT ROWID")
    db
  end

  def prepare
     @push = @queue.prepare("INSERT INTO _ul_queue_(queue, fire_at, value) VALUES ($1, (strftime('%s') + $2), $3) RETURNING fire_at || '-' || id")
     @pop = @queue.prepare("DELETE FROM _ul_queue_ WHERE (queue, fire_at, id) = (SELECT queue, min(fire_at), id FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at <= (unixepoch()) limit 1) RETURNING fire_at || '-' || id, value")
     @deleter = @queue.prepare("DELETE FROM _ul_queue_ WHERE queue = ifnull($1, 'default') AND fire_at = $2 AND id = $3 RETURNING value")
  end

end  



