require 'ultralite'
require './bench'
require 'redis'
require 'sqlite3'

cache = Ultralite::Cache.new # default settings
redis = Redis.new # default settings

values = []
keys = []
count = 10000

[10, 100, 1000, 10000].each do |size|
  count.times do
    keys << random_str(10) 
    values << random_str(size) 
  end
  
  random_keys = keys.shuffle
  puts "Tests for values of size #{size} bytes"
  puts "=========================================================="
  puts "== Writes =="
  bench("Ultralite cache writes", count) do |i|
    cache.set(keys[i], values[i])
  end

  bench("Redis writes", count) do |i|
    redis.set(keys[i], values[i])
  end

  puts "== Reads =="
  bench("Ultralite cache reads", count) do |i|
    cache.get(random_keys[i])
  end

  bench("Redis reads", count) do |i|
    redis.get(random_keys[i])
  end
  puts "=========================================================="


  keys = []
  values = []
end


cache.set("somekey", 1)
redis.set("somekey", 1)

bench("Ultralite cache increment") do
  cache.increment("somekey", 1)
end

bench("Redis increment") do
  redis.incr("somekey")
end

cache.clear
redis.flushdb

