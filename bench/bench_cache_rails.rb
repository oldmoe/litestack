require "active_support"
require_relative "../lib/litestack"
require_relative "bench"

cache = ActiveSupport::Cache::Litecache.new

# can only use the lookup method when the gem is installed
# cache = ActiveSupport::Cache.lookup_store(:litecache, {path: '../db/rails_cache.db'})

redis = ActiveSupport::Cache.lookup_store(:redis_cache_store, {})

values = []
keys = []
count = 1000

[10, 100, 1000, 10000].each do |size|
  count.times do
    keys << random_str(10)
    values << random_str(size)
  end

  random_keys = keys.shuffle
  puts "Benchmarks for values of size #{size} bytes"
  puts "=========================================================="
  puts "== Writes =="
  bench("litecache writes", count) do |i|
    cache.write(keys[i], values[i])
  end

  bench("Redis writes", count) do |i|
    redis.write(keys[i], values[i])
  end

  puts "== Multi Writes =="
  bench("litecache multi-writes", count / 5) do |i|
    idx = i * 5
    payload = {}
    5.times { |j| payload[keys[idx + j]] = values[idx + j] }
    cache.write_multi(payload)
  end

  bench("Redis multi-writes", count / 5) do |i|
    idx = i * 5
    payload = {}
    5.times { |j| payload[keys[idx + j]] = values[idx + j] }
    redis.write_multi(payload)
  end

  puts "== Reads =="
  bench("litecache reads", count) do |i|
    cache.read(random_keys[i])
  end

  bench("Redis reads", count) do |i|
    redis.read(random_keys[i])
  end

  puts "== Multi Reads =="
  bench("litecache multi-reads", count / 5) do |i|
    idx = i * 5
    payload = []
    5.times { |j| payload << random_keys[idx + j] }
    cache.read_multi(*payload)
  end

  bench("Redis multi-reads", count / 5) do |i|
    idx = i * 5
    payload = []
    5.times { |j| payload << random_keys[idx + j] }
    redis.read_multi(*payload)
  end

  puts "=========================================================="

  keys = []
  values = []
end

cache.write("somekey", 1, raw: true)

redis.write("somekey", 1, raw: true)

puts "Benchmarks for incrementing integer values"
puts "=========================================================="

bench("litecache increment", count) do
  cache.increment("somekey", 1, raw: true)
end

bench("Redis increment", count) do
  redis.increment("somekey", 1, raw: true)
end

cache.clear
redis.clear
