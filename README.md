# Ultralite

The ultimate IO toolkit for your Ruby applications. Ultralite containes a SQLite database adapter, a cache, a background job processing system and a full text search library. Ultralite provides integration with popular libraries, including:

- Sequel
- ActiveRecord
- ActiveSupport::Cache
- ActvieJob

With Ultralite you only need to add a single gem to your app which would replace a host of other gems and services, for example, a typical Rails app using Ultralite will no longer need the following services:

- PostgreSQL
- Redis
- Sidekiq
- ElasticSearch
- AnyCable
- Puma server

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

### SQL Database

You can use the bundeled Ultralite::DB adapter directly, or if you are using Sequel or ActiveRecord you can use them with Ultralite as follows

#### In ActiveRecord's database.yml

```yaml
adapter: ultralite
```

### Cache

### Jobs

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ultralite.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
