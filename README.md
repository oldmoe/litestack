![litestack](https://github.com/oldmoe/litestack/blob/master/assets/litestack_logo_teal_large.png?raw=true)


litestack is a revolutionary gem for Ruby and Ruby on Rails that provides an all-in-one solution for web application development. It includes a full-fledged SQL database, a fast cache, a robust job queue, and a simple yet performant full-text search all in a single package.

Compared to conventional approaches that require separate servers and databases, LiteStack offers superior performance, efficiency, ease of use, and cost savings. Its embedded database and cache reduce memory and CPU usage, while its simple interface streamlines the development process. Overall, LiteStack sets a new standard for web application development and is an excellent choice for those who demand speed, efficiency, and simplicity.

litestack provides integration with popular libraries, including:

- Rack
- Sequel
- Rails
- ActiveRecord
- ActiveSupport::Cache
- ActiveJob

With litestack you only need to add a single gem to your app which would replace a host of other gems and services, for example, a typical Rails app using Ultralite will no longer need the following services:

- PostgreSQL
- Redis
- Sidekiq

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

> ![litedb](https://github.com/oldmoe/litestack/blob/master/assets/litedb_logo_teal.png?raw=true)

litedb is a wrapper around SQLite3, offering a better default configuration that is tuned for concurrency and performance. Out of the box, litedb works seamlessly between multiple processes without database locking errors. lite db can be used in multiple ways, including:

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

litesd provides tight Rails/ActiveRecord integration and can be configured as follows

In database.yml

```yaml
adapter: litedb
# normal sqlite3 configuration follows
```

#### Sequel

litedb offers integration with the Sequel database toolkit and can be configured as follows

```ruby
DB = Sequel.conncet("litedb://path_to_db_file")    
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

litejob is a require 'litestack'
fast and very efficient job queue processor for Ruby applications. It builds on top of SQLite as well, which provides transactional guarantees, persistence and exceptional performance. 

#### Direct litejob usage
```ruby
require 'litestack'
# define your job class
class MyJob
  include ::litejob
      
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
    - [default 1]
    - [urgent 5]
    - [critical 10 "spawn"]
```

The queues need to include a name and a priority (a number between 1 and 10) and can also optionally add the token "spawn", which means every job will run it its own concurrency context (thread or fiber)


## Contributing

Bug reports aree welcome on GitHub at https://github.com/oldmoe/litestack. Please note that this is not an open contribution project and that we don't accept pull requests.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
