![litestack](https://github.com/oldmoe/litestack/blob/master/assets/litestack_logo_teal_large.png?raw=true)


litestack is a revolutionary gem for Ruby and Ruby on Rails that provides an all-in-one solution for web application development. It exploits the power and embeddedness of SQLite to include a full-fledged SQL database, a fast cache and a robust job queue all in a single package.

Compared to conventional approaches that require separate servers and databases, Litestack offers superior performance, efficiency, ease of use, and cost savings. Its embedded database and cache reduce memory and CPU usage, while its simple interface streamlines the development process. Overall, LiteStack sets a new standard for web application development and is an excellent choice for those who demand speed, efficiency, and simplicity.

You can read more about why litestack can be a good choice for your next web application **[here](WHYLITESTACK.md)**, you might also be interested in litestack **[benchmarks](BENCHMARKS.md)**.


litestack provides integration with popular libraries, including:

- Rack
- Sequel
- Rails
- ActiveRecord
- ActiveSupport::Cache
- ActiveJob
- ActionCable

With litestack you only need to add a single gem to your app which would replace a host of other gems and services, for example, a typical Rails app using litestack will no longer need the following services:

- Database Server (e.g. PostgreSQL, MySQL)
- Cache Server (e.g. Redis, Memcached)
- Job Processor (e.g. Sidekiq, Goodjob)
- Pubsub Server (e.g. Redis, PostgreSQL)

To make it even more efficient, litestack will detect the presence of Fiber based IO frameworks like Async (e.g. when you use the Falcon web server) or Polyphony. It will then switch its background workers for caches and queues to fibers (using the semantics of the existing framework). This is done transparently and will generally lead to lower CPU and memory utilization.

Litestack is still pretty young and under heavy development, but you are welcome to give it a try today!.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'litestack'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install litestack

## Usage

litestack currently offers three main components

- litedb
- litecache
- litejob
- litecable

> ![litedb](https://github.com/oldmoe/litestack/blob/master/assets/litedb_logo_teal.png?raw=true)

litedb is a wrapper around SQLite3, offering a better default configuration that is tuned for concurrency and performance. Out of the box, litedb works seamlessly between multiple processes without database locking errors. litedb can be used in multiple ways, including:

#### Direct litedb usage

litedb can be used exactly as the SQLite3 gem, since litedb iherits from SQLite3

```ruby
require 'litestack'
db = Litedb.new(path_to_db)
db.execute("create table users(id integer primary key, name text)")
db.execute("insert into users(name) values (?)", "Hamada")
db.get_first_value("select count(*) from users") # => 1
```

#### ActiveRecord

litedb provides tight Rails/ActiveRecord integration and can be configured as follows

In database.yml

```yaml
adapter: litedb
# normal sqlite3 configuration follows
```

#### Sequel

litedb offers integration with the Sequel database toolkit and can be configured as follows

```ruby
DB = Sequel.connect("litedb://path_to_db_file")
```


> ![litecache](https://github.com/oldmoe/litestack/blob/master/assets/litecache_logo_teal.png?raw=true)

litecache is a high speed, low overhead caching library that uses SQLite as its backend. litecache can be accessed from multiple processes on the same machine seamlessly. It also has features like key expiry, LRU based eviction and increment/decrement of integer values.

#### Direct litecache usage

```ruby
require 'litestack'
cache = Litecache.new(path: "path_to_file")
cache.set("key", "value")
cache.get("key") #=> "value"
```

#### ActiveResource::Cache

In your desired environment file (e.g. production.rb)

```ruby
config.cache_store = :litecache, {path: './path/to/your/cache/file'}
```
This provides a transparent integration that uses the Rails caching interface 

litecache spawns a background thread for cleanup purposes. In case it detects that the current environment has *Fiber::Scheduler* or *Polyphony* loaded it will spawn a fiber instead, saving on both memory and CPU cycles.

> ![litejob](https://github.com/oldmoe/litestack/blob/master/assets/litejob_logo_teal.png?raw=true)

More info about Litejob can be found in the [litejob guide](https://github.com/oldmoe/litestack/wiki/Litejob-guide)

litejob is a fast and very efficient job queue processor for Ruby applications. It builds on top of SQLite as well, which provides transactional guarantees, persistence and exceptional performance. 

#### Direct litejob usage
```ruby
require 'litestack'
# define your job class
class MyJob
  include ::Litejob
      
  queue = :default
      
  # must implement perform, with any number of params
  def perform(params)
    # do stuff
  end
end
    
#schedule a job asynchronusly
MyJob.perform_async(params)
    
#schedule a job at a certain time
MyJob.perform_at(time, params)
    
#schedule a job after a certain delay
MyJob.perform_after(delay, params)
```

#### ActiveJob

In your desired environment file (e.g. production.rb)

```ruby
config.active_job.queue_adapter = :litejob
```
#### Configuration file
You can add more configuration in litejob.yml (or config/litejob.yml if you are integrating with Rails)

```yaml
queues:
    - [default, 1]
    - [urgent, 5]
    - [critical, 10, "spawn"]
```

The queues need to include a name and a priority (a number between 1 and 10) and can also optionally add the token "spawn", which means every job will run it its own concurrency context (thread or fiber)

> ![litecable](https://github.com/oldmoe/litestack/blob/master/assets/litecable_logo_teal.png?raw=true)

#### ActionCable

This is a drop in replacement adapter for actioncable that replaces `async` and other production adapters (e.g. PostgreSQL, Redis). This adapter is currently only tested in local (inline) mode.

Getting up and running with litecable requires configuring your cable.yaml file under the config/ directory

cable.yaml
```yaml
development:
  adapter: litecable

test:
  adapter: test

staging:
  adapter: litecable

production:
  adapter: litecable
```

## Contributing

Bug reports are welcome on GitHub at https://github.com/oldmoe/litestack. Please note that this is not an open contribution project and that we don't accept pull requests.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
