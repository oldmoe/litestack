require "../lib/litestack"

# standard:disable Style/GlobalVars

class SomeAction
  include Litemetric::Measurable

  def initialize
    collect_metrics
  end

  def do1(param)
    capture("something", param)
  end

  def do2(param)
    capture("anotherthing", param)
  end

  def do3(param)
    measure("differentthing", param) do
      sleep 0.001
    end
  end

  def report
    resolution = "minute"
    puts topics = @litemetric.topics
    topics.each do |topic|
      puts topic
      puts events = @litemetric.event_names(resolution, topic)
      events.each do |event|
        if event[0] == "differentthing"
          puts keys = @litemetric.keys(resolution, topic, event[0])
          keys.each do |key|
            puts @litemetric.event_data(resolution, topic, event[0], key[0])
          end
        end
      end
    end
  end
end

some_action = SomeAction.new
$time = Time.now.to_i - 10800
lm = Litemetric.instance
def lm.current_time_slot
  ($time / 300) * 300
end
t = Time.now
40000.times do |i|
  $time += (rand * 100).to_i # extra 10 seconds
  action = ["do1", "do2", "do3"].sample
  some_action.send(action, "key_#{i}")
  puts "Finished #{i} events after #{Time.now - t} seconds" if i % 1000 == 0 && i > 0
end
puts "finished capturing, now reporting"
# some_action.report

# standard:enable Style/GlobalVars
