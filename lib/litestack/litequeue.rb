# frozen_stringe_literal: true

# all components should require the support module
require_relative "litesupport"

# require 'securerandom'

##
# Litequeue is a simple queueing system for Ruby applications that allows you to push and pop values from a queue. It provides a straightforward API for creating and managing named queues, and for adding and removing values from those queues. Additionally, it offers options for scheduling pops at a certain time in the future, which can be useful for delaying processing until a later time.
#
# Litequeue is built on top of SQLite, which makes it very fast and efficient, even when handling large volumes of data. This lightweight and easy-to-use queueing system serves as a good foundation for building more advanced job processing frameworks that require basic queuing capabilities.
#

class Litequeue
  # the default options for the queue
  # can be overriden by passing new options in a hash
  # to Litequeue.new
  #   path: "./queue.db"
  #   mmap_size: 128 * 1024 * 1024 -> 128MB to be held in memory
  #   sync: 1 -> sync only when checkpointing

  include Litesupport::Liteconnection

  DEFAULT_OPTIONS = {
    path: Litesupport.root.join("queue.sqlite3"),
    mmap_size: 32 * 1024,
    sync: 0
  }

  # create a new instance of the litequeue object
  # accepts an optional options hash which will be merged with the DEFAULT_OPTIONS
  #   queue = Litequeue.new
  #   queue.push("somevalue", 2) # the value will be ready to pop in 2 seconds
  #   queue.pop # => nil
  #   sleep 2
  #   queue.pop # => "somevalue"

  def initialize(options = {})
    init(options)
  end

  # push an item to the queue, optionally specifying the queue name (defaults to default) and after how many seconds it should be ready to pop (defaults to zero)
  # a unique job id is returned from this method, can be used later to delete it before it fires. You can push string, integer, float, true, false or nil values
  #
  def push(value, delay = 0, queue = "default")
    # @todo - check if queue is busy, back off if it is
    # also bring back the synchronize block, to prevent
    # a race condition if a thread hits the busy handler
    # before the current thread proceeds after a backoff
    # id = SecureRandom.uuid # this is somehow expensive, can we improve?
    run_stmt(:push, queue, delay, value)[0]
  end

  def repush(id, value, delay = 0, queue = "default")
    @conn.acquire do |c|
      c.transaction(:immediate) do
        c.stmts[:delete].execute!(id)
        c.stmts[:repush].execute!([id, queue, delay, value])[0]
      end
    end
  end

  def register_worker(worker_id)
    run_stmt(:register_worker, worker_id)
  end

  def worker_heartbeat(worker_id)
    run_stmt(:worker_heartbeat, worker_id)
  end

  alias_method :<<, :push
  alias_method :"<<<", :repush

  # pop an item from the queue, optionally with a specific queue name (default queue name is 'default')
  def pop(worker_id, queue = "default")
    res = run_stmt(:pop, worker_id, queue)
    return res[0] if res.length == 1
    return nil if res.empty?
    res
  end

  def clear_dead_workers(cutoff_time)
    res = run_stmt(:clear_dead_workers, cutoff_time)
    return res[0] if res.length == 1
    return nil if res.empty?
    res
  end

  def workers
    run_stmt(:get_workers)
  end

  def clear_dead_jobs(count)
    res = run_stmt(:clear_dead_jobs, count)
    return res[0] if res.length == 1
    return nil if res.empty?
    res
  end

  def rescue_abandoned_jobs
    run_stmt(:rescue_abandoned_jobs)
  end

  # delete an item from the queue
  #   queue = Litequeue.new
  #   id = queue.push("somevalue")
  #   queue.delete(id) # => "somevalue"
  #   queue.pop # => nil
  def delete(id)
    run_stmt(:delete, id)[0]
  end

  # deletes all the entries in all queues, or if a queue name is given, deletes all entries in that specific queue
  def clear(queue = nil)
    run_sql("DELETE FROM queue WHERE iif(?1 IS NOT NULL, name = ?1,  TRUE)", queue)
  end

  # returns a count of entries in all queues, or if a queue name is given, reutrns the count of entries in that queue
  def count(queue = nil)
    run_sql("SELECT count(*) FROM queue WHERE iif(?1 IS NOT NULL, name = ?1, TRUE)", queue)[0][0]
  end

  # return the size of the queue file on disk
  # def size
  #  run_sql("SELECT size.page_size * count.page_count FROM pragma_page_size() AS size, pragma_page_count() AS count")[0][0]
  # end

  def queues_info
    run_stmt(:info)
  end

  def snapshot
    queues = {}
    queues_info.each do |qc|
      # queues[qc[0]] = {count: qc[1], time_in_queue: {avg: qc[2], min: qc[3], max: qc[4]}}
      queues[qc[0]] = qc[1]
    end
    {
      summary: {
        path: path,
        journal_mode: journal_mode,
        synchronous: synchronous,
        size: size,
        jobs: count
      },
      queues: queues
    }
  end

  private

  def create_connection
    super("#{__dir__}/litequeue.sql.yml") do |conn|
      conn.wal_autocheckpoint = 10000
      # check if there is an old database and convert entries to the new format
      if conn.get_first_value("select count(*) from sqlite_master where name = '_ul_queue_'") == 1
        conn.transaction(:immediate) do
          conn.execute("INSERT INTO queue(fire_at, name, value, created_at) SELECT fire_at, queue, value, created_at FROM _ul_queue_")
          conn.execute("DROP TABLE _ul_queue_")
        end
      end
    end
  end
end
