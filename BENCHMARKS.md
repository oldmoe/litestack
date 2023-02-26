# Litestack Benchmarks

This is a set of initial (simple) benchmars, designed to understand the baseline performance for different litestack components against their counterparts. 
These are not real life scenarios and I hope I will be able to produce some interesting ones soon.

> ![litedb](https://github.com/oldmoe/litestack/blob/master/assets/litedb_logo_teal.png?raw=true)

### Point Read

```ruby
Post.find(id) #ActiveRecord
Post[id] #Sequel
```
This maps to "SELECT * FROM posts WHERE id = ?"

|Prcoess Count|ActiveRecord:PostgreSQL|ActiveRecord:litedb|Sequel:PostgreSQL|Sequel:litedb|
|-:|-:|-:|-:|-:|
|1|1.3K q/s|6.5K q/s|1.8K q/s|17.4K q/s|
|2|2.6K q/s|13.9K q/s|3.5K q/s|33.2K q/s|
|4|4.9K q/s|24.5K q/s|5.9K q/s|58.7K q/s|
|8|6.9K q/s|31.8K q/s|9.3K q/s|86.6K q/s|

### Multi Reads

```ruby
Post.where(user_id: id).limit(5) # ActiveRecord and Sequel
```
This maps to "SELECT * FROM posts WHERE user_id = ? LIMIT 5"

|Prcoess Count|ActiveRecord:PostgreSQL|ActiveRecord:litedb|Sequel:PostgreSQL|Sequel:litedb|
|-:|-:|-:|-:|-:|
|1|345 q/s|482 q/s|937 q/s|1.1K q/s|
|2|751 q/s|848 q/s|1.3K q/s|2.3K q/s|
|4|1.4K q/s|1.6K q/s|3.4K q/s|4.0K q/s|
|8|2.6K q/s|2.8K q/s|5.1K q/s|6.6K q/s|

### Point Update

```ruby
Post.update(id, {updated_at: updated_at} # ActiveRecord
Post[id].update({updated_at: updated_at}) # Sequel
```
This maps to "Update posts SET updated_at = ? WHERE id = ?"

|Prcoess Count|ActiveRecord:PostgreSQL|ActiveRecord:litedb|Sequel:PostgreSQL|Sequel:litedb|
|-:|-:|-:|-:|-:|
|1|125 q/s|484 q/s|129 q/s|2.1K q/s|
|2|265 q/s|576 q/s|333 q/s|2.5K q/s|
|4|481 q/s|693 q/s|704 q/s|2.3K q/s|
|8|898 q/s|748 q/s|1.2K q/s|2.4K q/s|

It is clear the Litedb enjoys a clear advantage for reads and is very competitive for updates until many processes are relentlessly trying to write at the same time non stop.
For most applications, even with higher level of concurrency, Litedb will scale super well for reads and provide a very good baseline for writes.

> ![litecache](https://github.com/oldmoe/litestack/blob/master/assets/litecache_logo_teal.png?raw=true)

For testing the cache we attempted to try writing and reading different payload sizes with a fixed key size

### Write

|Payload Size (bytes)|Redis|litecahce|
|-:|-:|-:|
|10|4.2K q/s|11.0K q/s|
|100|4.7K q/s|11.6K q/s|
|1000|4.0K q/s|7.0K q/s|
|10000|3.4K q/s|2.4K q/s|

### Read

|Payload Size (bytes)|Redis|litecahce|
|-:|-:|-:|
|10|5.0K q/s|69.4K q/s|
|100|5.0K q/s|90.7K q/s|
|1000|4.5K q/s|70.9K q/s|
|10000|3.7K q/s|26.9K q/s|

### Increment an int value

|Redis|litecahce|
|-:|-:|
|5.1K q/s|16.9K q/s|

It is not even a contest! litecache delivers way higher peroformance, specially in reading performance which is arguably the most important metric for a cache.

> ![litejob](https://github.com/oldmoe/litestack/blob/master/assets/litejob_logo_teal.png?raw=true)

Two scenarios were benchmarked, an empty job and one with a 100ms sleep to simulate moderate to heavy network IO. Sidekiq was tested against litejob

### No-op Job

|Sidekiq|Litejob:threads|litejob:fibers|
|-:|-:|-:|
|1.4K j/s|1.6K j/s|4.9K j/s|

### IO Simulated Job

|Sidekiq: 5 threads|Sidekiq: 25 threads|Litejob:threads|litejob:fibers|
|-:|-:|-:|-:|
|48 j/s|239 j/s|457 j/s|3.2K j/s|

Running Litejob with fibers is producing much faster results than any threaded solution. Still though, threaded Litejob remains ahead of Sidekiq in all scenarios. 



