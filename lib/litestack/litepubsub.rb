# frozen_stringe_literal: true

# all components should require the support module
require_relative 'litesupport'

class Litepubsub

  def initialize
    @engine = SQLite3::Database.new("pubsub.db")
    @engine.synchronous = 0
    @engine.journal_mode = "WAL"
    @engine.execute("create table if not exists channels(id integer primary key autoincrement, channel text, message text, created_at integer default(unixepoch()))")
    @engine.execute("create index if not exists channels_cai on channels(created_at)")
    @publisher = @engine.prepare("insert into channels(channel, message) values ($1, $2)")
    @poller = @engine.prepare("select id, channel, message from channels where id > ? order by id asc")
    @cleaner = @engine.prepare("delete from channels where created_at < (unixepoch() - 10)")
    @channels = {}
    @listener = create_listener
    @gc_worker = create_gc_worker
    @running = true
    p @max_id = @engine.get_first_value("select max(id) from channels") || 0
  end
  
  def publish(channel, msg)
    @publisher.execute!(channel, msg)
    #puts "published msg #{msg} to channel #{channel}"
  end
  
  def subscribe(channel, client)
    @channels[channel] = {} unless @channels[channel]
    @channels[channel][client] = true 
    p @channels
  end
  
  def unsubsctibe(channel, client)
    @channels[channel].delete(client)
  end

  def create_listener
    Litesupport.spawn do
      while @running
        # check for new elements in listening channels
        new_elements = @poller.execute!(@max_id).to_a
        channels = {}
        if new_elements.length > 0
          @max_id = new_elements.last[0]
          new_elements.each do |e|
            channels[e[1]] = [] unless channels[e[1]]
            channels[e[1]] << e[2]
          end
          channels.each_pair do |channel, msgs|
            @channels[channel].each_pair do |subscriber, _|
              msgs.each {|msg| subscriber.send msg }
            end
          end
        end
        sleep 0.01
      end
    end
  end
  
  
  def create_gc_worker
    Litesupport.spawn do
      while @running
        # delete old topics in listening channels
        @cleaner.execute!
        puts "deleted #{@engine.changes}"
        sleep 5
      end
    end
  end
  
end

class Client
  def initialize(name)
    @name = name
  end

  def send(msg)
    #puts "client #{@name} received #{msg}"
  end

end


litepubsub = Litepubsub.new

client1 = Client.new("samir")
client2 = Client.new("shahir")
client3 = Client.new("bahir")

litepubsub.subscribe("c1", client1)
litepubsub.subscribe("c2", client1)
litepubsub.subscribe("c3", client1)
litepubsub.subscribe("c1", client2)
litepubsub.subscribe("c2", client2)
litepubsub.subscribe("c1", client3)

#sleep 1

t = Time.now
10000.times do |i|
  litepubsub.publish("c1", "Ahlan #{i+1}")
  litepubsub.publish("c2", "Wa #{i+1}")
  litepubsub.publish("c3", "Sahlan #{i+1}")
end
puts Time.now - t

sleep
