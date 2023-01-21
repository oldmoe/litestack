require 'sqlite3'

def bench(msg, iterations=1000)
  GC.start
  GC.compact
  print "Starting #{iterations} iterations of #{msg} ... "
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iterations.times do |i|
    yield i
  end
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  time = ((t2 - t1)*1000).to_i.to_f / 1000 rescue 0
  ips = ((iterations/time)*100).to_i.to_f / 100 rescue "infinity?"
  #{m: msg, t: time, ips: iteratinos/time, i: iterations}
  puts "finished in #{time} seconds (#{ips} ips)"
end

@db = SQLite3::Database.new(":memory:") # sqlite database for fast random string generation

def random_str(size)
  @db.get_first_value("select hex(randomblob(?))", size)
end 

