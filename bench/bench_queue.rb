require './bench'
require 'ultralite'

count = 100000

q = Ultralite::Queue.new

bench("enqueue", count) do |i|
  q.push i.to_s
end

bench("dequeue", count) do |i|
  q.pop  
end


