![litestack](https://github.com/oldmoe/litestack/blob/master/assets/litestack_logo_teal_large.png?raw=true)

<a href="https://badge.fury.io/rb/litestack" target="_blank"><img height="21" style='border:0px;height:21px;' border='0' src="https://badge.fury.io/rb/litestack.svg" alt="Gem Version"></a>
<a href='https://rubygems.org/gems/litestack' target='_blank'><img height='21' style='border:0px;height:21px;' src='https://img.shields.io/gem/dt/litestack?color=brightgreen&label=Rubygems%20Downloads' border='0' alt='RubyGems Downloads' /></a>

All your data infrastructure, in a gem!

Litestack is a Ruby gem that provides both Ruby and  Ruby on Rails applications an all-in-one solution for web application data infrastructure. It exploits the power and embeddedness of SQLite to deliver a full-fledged SQL database, a fast cache , a robust job queue, a reliable message broker, a full text search engine and a metrics platform all in a single package.

Compared to conventional approaches that require separate servers and databases, Litestack offers superior performance, efficiency, ease of use, and cost savings. Its embedded database and cache reduce memory and CPU usage, while its simple interface streamlines the development process. Overall, Litestack sets a new standard for web application development and is an excellent choice for those who demand speed, efficiency, and simplicity.

You can read more about why litestack can be a good choice for your next web application **[here](WHYLITESTACK.md)**, you might also be interested in litestack **[benchmarks](BENCHMARKS.md)**.

With litestack you only need to add a single gem to your app which would replace a host of other gems and services, for example, a typical Rails app using litestack will no longer need the following services:

- Database Server (e.g. PostgreSQL, MySQL)
- Cache Server (e.g. Redis, Memcached)
- Job Processor (e.g. Sidekiq, Goodjob)
- Pubsub Server (e.g. Redis, PostgreSQL)
- Fulltext Search Server (e.g. Elasticsearch, Meilisearch)

To make it even more efficient, litestack will detect the presence of Fiber based IO frameworks like Async (e.g. when you use the Falcon web server) or Polyphony. It will then switch its background workers for caches and queues to fibers (using the semantics of the existing framework). This is done transparently and will generally lead to lower CPU and memory utilization.
![litestack](https://github.com/oldmoe/litestack/blob/master/assets/litestack_advantage.png?raw=true)

## Installation

Add the `litestack` gem line to your application's Gemfile:

    $ bundle add litestack

To configure a Rails application to run the full litestack, run:

    $ rails generate litestack:install

## Usage

litestack currently offers six main components

- litedb
- litecache
- litejob
- litecable
- litesearch
- litemetric

> ![litedb](https://github.com/oldmoe/litestack/blob/master/assets/litedb_logo_teal.png?raw=true)

litedb is a wrapper around SQLite3, offering a better default configuration that is tuned for concurrency and performance. Out of the box, litedb works seamlessly between multiple processes without database locking errors. litedb can be used in multiple ways, including:

#### Direct litedb usage

litedb can be used exactly as the SQLite3 gem, since litedb inherits from SQLite3

```ruby
require 'litestack'
db = Litedb.new(path_to_db)
db.execute("create table users(id integer primary key, name text)")
db.execute("insert into users(name) values (?)", "Hamada")
db.query("select count(*) from users") # => [[1]]
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

> ![litesearch](https://github.com/oldmoe/litestack/blob/master/assets/litesearch_logo_teal.png?raw=true)

### Litesearch

Litesearch adds full text search capabilities to Litedb, you can use it in standalone mode as follows:

```ruby
require 'litestack/litedb'
db = Litedb.new(":memory:")
# create the index
idx = db.search_index('index_name') do |schema|
    schema.fields [:sender, :receiver, :body]
    schema.field :subject, weight: 10
    schema.tokenizer :trigram
end
# add documents
idx.add({sender: 'Kamal', receiver: 'Laila', subject: 'Are the girls awake?', body: 'I got them the new phones they asked for, are they awake?'})
# search the index, all fields
idx.search('kamal')
# search the index, specific field, partial workd (trigram)
idx.search('subject: awa') 
```

Litesearch integrates tightly with ActiveRecord and Sequel, here are integration examples

#### ActiveRecord

```ruby
class Author < ActiveRecord::Base
    has_many :books
end

class Book < ActiveRecord::Base
    belongs_to :author

    include Litesearch::Model

    litesearch do |schema|
        schema.fields [:title, :description]
        schema.field :author, target: 'authors.name'
        schema.tokenizer :porter
    end
end
# insert records
Author.create(name: 'Adam A. Writer') 
Book.create(title: 'The biggest stunt', author_id: 1, description: 'a description') 
# search the index, the search method integrates with AR's query interface
Book.search('author: writer').limit(1).all
```
#### Sequel

```ruby
class Author < Sequel::Model
    one_to_many :books
end

class Book < Sequel::Model
    many_to_one :author

    include Litesearch::Model
    litesearch do |schema|
        schema.fields [:title, :description]
        schema.field :author, target: 'authors.name'
        schema.tokenizer :porter
    end
end
# insert records
Author.create(name: 'Adam A. Writer') 
Book.create(title: 'The biggest stunt', author_id: 1, description: 'a description') 
# search the index, the search method integrates with Sequel's query interface
Book.search('author: writer').limit(1).all
```

> ![litemetric](https://github.com/oldmoe/litestack/blob/master/assets/litemetric_logo_teal.png?raw=true)

### Litemetric
Litestack comes with a module that can collect useful metrics for its different components, in each component, you need to add the following to the respective .yml file (database.yml in case of Litedb)
```yml
    metrics: true # default is false
```
If you have the metrics enabled, it will start collecting data from the various modules and will store them in a database file called metric.db located in the Litesupport.root folder

Litemetric has an API that would enable collecting arbitrary metrics for non-litestack classes. The metrics will be in the database but currently the Liteboard is only able to show correct data for Litestack modules, displaying arbitrary metrics for other components will be included later.

### Liteboard
Liteboard is a simple web server that provides a web interface for the collected metrics, it should be available globally, for usage instructions type
```
    liteboard -h
```
It allows you to point to a specific metrics database file or a config file and then it will display the data in that metrics database

Example metrics views:

#### Litedb
![litedb](https://github.com/oldmoe/litestack/blob/master/assets/litedb_metrics.png?raw=true)

- Database size, number of tables & indexes
- Number of read/write queries
- Read/Write query ratio over time
- Read/Write query time over time
- Slowest queries
- Most expensive queries (total run time = frequency * cost)

#### Litecache
![litecache](https://github.com/oldmoe/litestack/blob/master/assets/litecache_metrics.png?raw=true)

- Cache size, % of size limit
- Number of entries
- Reads/Writes over time
- Read hits/misses over time
- Most written entries
- Most read entries 

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/oldmoe/litestack.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
