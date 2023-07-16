# frozen_string_literal: true
require 'hanami/router'
require 'tilt'
require 'erubi'

# require relative so we pick the gem version that corresponds to the liteboard binary
require_relative '../../litestack/litemetric'

class Liteboard 

  @@resolutions = {'minute' => [300, 12], 'hour' => [3600, 24], 'day' => [3600*24, 7], 'week' => [3600*24*7, 53], 'year' => [3600*24*365, 100] }
  @@res_mapping = {'hour' => 'minute', 'day' => 'hour', 'week' => 'day', 'year' => 'week'}
  @@templates = {}
  @@app = Hanami::Router.new do

    get "/", to: ->(env) do
      Liteboard.new(env).call(:index)
    end
    
    get "/topics/:topic", to: ->(env) do
      Liteboard.new(env).call(:topic)
    end
    
    get "/topics/:topic/events/:event", to: ->(env) do
      Liteboard.new(env).call(:event)
    end

  end 


  def initialize(env)
    @env = env
    @params = @env["router.params"]
    @running = true
    @lm = Litemetric.instance
  end

  def params(key)    
    URI.decode_uri_component("#{@params[key]}")
  end

  def call(method)
    before
    res = send(method)
    after(res)
  end
  
  def render(tpl_name)
    layout = Tilt.new("#{__dir__}/views/layout.erb")
    tpl = Tilt.new("#{__dir__}/views/#{tpl_name.to_s}.erb")
    res = layout.render(self){tpl.render(self)}
  end

  def after(body=nil)
    [200, {'Cache-Control' => 'no-cache'}, [body]]    
  end

  def before
    @res = params(:res) || 'day'
    @resolution = @@res_mapping[@res]
    if not @resolution
      @res = 'day'
      @resolution = @@res_mapping[@res]      
    end
    @step = @@resolutions[@resolution][0]
    @count = @@resolutions[@resolution][1]
    @order = params(:order) 
    @order = nil if @order == ''
    @dir = params(:dir) 
    @dir = 'desc' if @dir.nil? || @dir == ''
    @dir = @dir.downcase
    @idir = if @dir == "asc"
      "desc"
    else
      "asc"
    end
    @search = params(:search)
    @search = nil if @search == ''
  end
  
  def index
    @order = 'topic' unless @order
    topics = @lm.topics
    @topics = @lm.topic_summaries(@resolution, @step * @count, @order, @dir, @search)
    @topics.each do |topic|
        data_points = @lm.topic_data_points(@step, @count, @resolution, topic[0])      
        topic << data_points.collect{|r| [r[0],r[2]]}
    end    
    render :index
  end
  
  def topic
    @order = 'rcount' unless @order
    @topic = params(:topic)
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event[0])
      event << data_points.collect{|r| [r[0],r[2]]}
      event << data_points.collect{|r| [r[0],r[3]]}
    end
    @snapshot = @lm.snapshot(@topic)
    if @snapshot.empty?
      @snapshot = []
    else
      @snapshot[0] = Oj.load(@snapshot[0]) unless @snapshot[0].nil?
    end
    render :topic
  end
  
  def event
    @order = 'rcount' unless @order
    @topic = params(:topic)
    @event = params(:event)
    @keys = @lm.keys_summaries(@topic, @event, @resolution, @order, @dir, @search, @step * @count)  
    @keys.each do |key|
      data_points = @lm.key_data_points(@step, @count, @resolution, @topic, @event, key[0])
      key << data_points.collect{|r| [r[0],r[2]]}
      key << data_points.collect{|r| [r[0],r[3]]}
    end    
    render :event
  end

  def index_sort_url(field)
    "/?#{compose_query(field)}"
  end
  
  def topic_sort_url(field)
    "/topics/#{encode(@topic)}?#{compose_query(field)}"
  end
  
  def event_sort_url(field)
    "/topics/#{encode(@topic)}/events/#{encode(@event)}?#{compose_query(field)}"
  end
  
  def compose_query(field)
    field.downcase!
    "res=#{@res}&order=#{field}&dir=#{@order == field ? @idir : @dir}&search=#{@search}"
  end
  
  def sorted?(field)
    @order == field
  end
  
  def dir(field)
    if sorted?(field)
      if @dir == 'asc'
        return "<span class='material-icons'>arrow_drop_up</span>"  
      else
        return "<span class='material-icons'>arrow_drop_down</span>"
      end
    end
    '&nbsp;&nbsp;'
  end
  
  def encode(text)
    URI.encode_uri_component(text)
  end
  
  def self.app
   @@app
  end

end




#Rack::Server.start({app: Litebaord.app, daemonize: false})
