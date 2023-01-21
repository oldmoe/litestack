require 'ultralite'
require 'active_support'
require './bench'

sql = {
  :pruner => <<-SQL
    ABC
  SQL,
  :extra => <<-SQL
    sdsd 
  SQL
  
}

cache = ActiveSupport::Cache.lookup_store(:ultralite_cache_store, {})
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
  puts "Tests for values of size #{size} bytes"
  puts "=========================================================="
  puts "== Writes =="
  bench("Ultralite cache writes", count) do |i|
    cache.write(keys[i], values[i])
  end

  bench("Redis writes", count) do |i|
    redis.write(keys[i], values[i])
  end

  puts "== Reads =="
  bench("Ultralite cache reads", count) do |i|
    cache.read(random_keys[i])
  end

  bench("Redis reads", count) do |i|
    redis.read(random_keys[i])
  end
  puts "=========================================================="


  keys = []
  values = []
end


cache.write("somekey", 1)
redis.write("somekey", 1)

bench("Ultralite cache increment") do
  cache.increment("somekey", 1)
end

bench("Redis increment") do
  redis.increment("somekey")
end

cache.clear
redis.clear

