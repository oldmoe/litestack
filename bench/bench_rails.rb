require 'ultralite'
require 'active_support'
require './bench'

cache = ActiveSupport::Cache.lookup_store(:ultralite_cache_store, {})
mem = ActiveSupport::Cache.lookup_store(:ultralite_cache_store, {path: ":memory:"})
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
  bench("Ultralite cache writes", count) do |i|
    cache.write(keys[i], values[i])
  end

  bench("Ultralite memory cache writes", count) do |i|
    mem.write(keys[i], values[i])
  end

  bench("Redis writes", count) do |i|
    redis.write(keys[i], values[i])
  end

  puts "== Reads =="
  bench("Ultralite cache reads", count) do |i|
    cache.read(random_keys[i])
  end

  bench("Ultralite memory cache reads", count) do |i|
    mem.read(random_keys[i])
  end

  bench("Redis reads", count) do |i|
    redis.read(random_keys[i])
  end
  puts "=========================================================="


  keys = []
  values = []
end


cache.write("somekey", 1, raw: true)
#puts cache.read("somekey", raw: true)

mem.write("somekey", 1, raw: true)
#puts mem.read("somekey", raw: true)

redis.write("somekey", 1, raw: true)
#puts redis.read("somekey", raw: true)

puts "Benchmarks for incrementing integer values"
puts "=========================================================="

bench("Ultralite cache increment", count) do
  cache.increment("somekey", 1, raw: true)
end

bench("Ultralite memory cache increment", count) do
  mem.increment("somekey", 1, raw: true)
end

bench("Redis increment", count) do
  redis.increment("somekey", 1, raw: true )
end

cache.clear
redis.clear

