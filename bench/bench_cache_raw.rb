require "redis"
require "sqlite3"
require_relative "bench"

# require 'polyphony'
require "async/scheduler"

Fiber.set_scheduler Async::Scheduler.new
Fiber.scheduler.run

require_relative "../lib/litestack/litecache"
# require 'litestack'

cache = Litecache.new # ({path: "../db/cache.db"}) # default settings
redis = Redis.new # default settings

values = []
keys = []
count = 1000
count.times { keys << random_str(10) }

[10, 100, 1000, 10000].each do |size|
  count.times do
    values << random_str(size)
  end

  random_keys = keys.shuffle

  GC.compact

  puts "Benchmarks for values of size #{size} bytes"
  puts "=========================================================="
  puts "== Writes =="
  bench("litecache writes", count) do |i|
    cache.set(keys[i], values[i])
  end

  bench("Redis writes", count) do |i|
    redis.set(keys[i], values[i])
  end

  puts "== Multi Writes =="
  bench("litecache multi-writes", count / 5) do |i|
    idx = i * 5
    payload = {}
    5.times { |j| payload[keys[idx + j]] = values[idx + j] }
    cache.set_multi(payload)
  end

  bench("Redis multi-writes", count / 5) do |i|
    idx = i * 5
    payload = []
    5.times { |j|
      payload << keys[idx + j]
      payload << values[idx + j]
    }
    redis.mset(*payload)
  end

  puts "== Reads =="
  bench("litecache reads", count) do |i|
    cache.get(random_keys[i])
  end

  bench("Redis reads", count) do |i|
    redis.get(random_keys[i])
  end

  puts "== Multi Reads =="
  bench("litecache multi-reads", count / 5) do |i|
    idx = i * 5
    payload = []
    5.times { |j| payload << random_keys[idx + j] }
    cache.get_multi(*payload)
  end

  bench("Redis multi-reads", count / 5) do |i|
    idx = i * 5
    payload = []
    5.times { |j| payload << random_keys[idx + j] }
    redis.mget(*payload)
  end

  puts "=========================================================="

  values = []
end

cache.set("somekey", 1)
redis.set("somekey", 1)

bench("litecache increment") do
  cache.increment("somekey", 1)
end

bench("Redis increment") do
  redis.incr("somekey")
end

cache.clear
redis.flushdb

# sleep
