require 'redis'
require 'sqlite3'
require_relative './bench'

#require 'polyphony'
require 'async/scheduler'

Fiber.set_scheduler Async::Scheduler.new
Fiber.scheduler.run

require_relative '../lib/litestack/litecache'
#require 'litestack'

cache = Litecache.new({path: '../db/cache.db'}) # default settings
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

  #bench("file writes", count) do |i|
  #  f = File.open("../files/#{keys[i]}.data", 'w+')
  #  f.write(values[i])
  #  f.close
  #end
  

  bench("Redis writes", count) do |i|
    redis.set(keys[i], values[i])
  end

  puts "== Reads =="
  bench("litecache reads", count) do |i|
    cache.get(random_keys[i])
  end

  #bench("file reads", count) do |i|
  #  data = File.read("../files/#{keys[i]}.data")
  #end

  bench("Redis reads", count) do |i|
    redis.get(random_keys[i])
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

#sleep

