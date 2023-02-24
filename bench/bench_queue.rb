require './bench'
require_relative '../lib/litestack'

count = 1000

q = Litequeue.new({path: '../db/queue.db' })

bench("enqueue", count) do |i|
  q.push i.to_s
end

bench("dequeue", count) do |i|
  q.pop  
end


