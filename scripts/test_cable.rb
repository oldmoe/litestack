require_relative "../lib/litestack/litecable"

# fork

lc = Litecable.new({logger: "STDOUT", metrics: true})

class Client
  def initialize(channel)
    @channel = channel
    warn "[#{Process.pid}]:#{object_id} listening to #{@channel}"
  end

  def call(*args)
    warn "[#{Process.pid}]:#{object_id} received #{args} from #{@channel}"
  end
end

channels = []
5.times { |i| channels << "channel##{i + 1}" }

20.times do
  channel = channels.sample
  lc.subscribe(channel, Client.new(channel))
end

100.times do |i|
  lc.broadcast(channels.sample, "message##{i + 1}")
end

sleep
