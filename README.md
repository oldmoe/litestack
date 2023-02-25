# litestack

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

### Rails

litestack provides tight Rails integration and can be configured as follows

#### ActiveRecord

In database.yml

```yaml
adapter: litedb
```

#### Cache

In your desired environment file (e.g. production.rb)

```ruby
config.cache_store = :litecache, {path: './path/to/your/cache/file'}
```


#### Jobs

In your desired environment file (e.g. production.rb)

```ruby
config.active_job.queue_adapter = :litejob
```

You can add more configuration in config/litejob.yml

```yaml
queues:
    - [default 1]
    - [urgent 5]
    - [critical 10 "spawn"]
```

The queues need to include a name and a priority (a number between 1 and 10) and can also optionally add the token "spawn", which means every job will run it its own concurrency context (thread or fiber)

## Contributing

Bug reports aree welcome on GitHub at https://github.com/oldmoe/ultralite. Please note that this is not an open contribution project and that we don't accept pull requests.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
