# Ultralite

Ultralite is a revolutionary gem for Ruby and Ruby on Rails that provides an all-in-one solution for web application development. It includes a full-fledged SQL database, a fast cache, a robust job queue, and a simple yet performant full-text search all in a single package.

Compared to conventional approaches that require separate servers and databases, LiteStack offers superior performance, efficiency, ease of use, and cost savings. Its embedded database and cache reduce memory and CPU usage, while its simple interface streamlines the development process. Overall, LiteStack sets a new standard for web application development and is an excellent choice for those who demand speed, efficiency, and simplicity.

Ultralite provides integration with popular libraries, including:

- Rack
- Sequel
- Rails
- ActiveRecord
- ActiveSupport::Cache
- ActiveJob

With Ultralite you only need to add a single gem to your app which would replace a host of other gems and services, for example, a typical Rails app using Ultralite will no longer need the following services:

- PostgreSQL
- Redis
- Sidekiq

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ultralite'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ultralite

## Usage

### Rails

Ultralite provides tight Rails integration and can be configured as follows

#### ActiveRecord

In database.yml

```yaml
adapter: ultralite
```

#### Cache

In your desired environment file (e.g. production.rb)

```ruby
config.cache_store = :ultralite_cache_store, {path: './path/to/your/cache/file'}
```


#### Jobs

In your desired environment file (e.g. production.rb)

```ruby
config.active_job.queue_adapter = :ultralite
```

You can add more configuration in config/ultrajob.yml

```yaml
queues:
    - [default 1]
    - [urgent 5]
    - [critical 10]
```
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/oldmoe/ultralite.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
