require './bench'
require 'ultralite'

count = 10000
t = Time.now.to_f

q = Ultralite::Queue.new
t = Time.now 
count.times do |i|
  q.push i.to_s
end
puts Time.now - t

count.times do |i|
  q.pop  
end
puts Time.now - t


