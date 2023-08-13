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

    get "/topics/Litejob", to: ->(env) do
      Liteboard.new(env).call(:litejob)
    end

    get "/topics/Litecache", to: ->(env) do
      Liteboard.new(env).call(:litecache)
    end
    
    get "/topics/Litedb", to: ->(env) do
      Liteboard.new(env).call(:litedb)
    end

    get "/topics/Litecable", to: ->(env) do
      Liteboard.new(env).call(:litecable)
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
    @topics = @lm.topic_summaries(@resolution, @step * @count, @order, @dir, @search)
  end
  
  def index
    @order = 'topic' unless @order
    @topics.each do |topic|
        data_points = @lm.topic_data_points(@step, @count, @resolution, topic[0])      
        topic << data_points.collect{|r| [r[0],r[2] || 0]}
    end    
    render :index
  end
  
  def litecache
    @order = 'rcount' unless @order
    @topic = 'Litecache'
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event['name'])
      event['counts'] = data_points.collect{|r| [r['rtime'],r['rcount']]}
      event['values'] = data_points.collect{|r| [r['rtime'],r['ravg']]}
    end
    @snapshot = read_snapshot(@topic)
    @size = @snapshot[0][:summary][:size] rescue 0
    @max_size = @snapshot[0][:summary][:max_size] rescue 0
    @full = (@size / @max_size)*100 rescue 0
    @entries = @snapshot[0][:summary][:entries] rescue 0
    @gets = @events.find{|t| t['name'] == 'get'}
    @sets = @events.find{|t| t['name'] == 'set'}
    @reads = @gets['rcount'] rescue 0
    @writes = @sets['rcount'] rescue 0
    @hitrate = @gets['ravg'] rescue 0
    @hits = @reads * @hitrate
    @misses = @reads - @hits
    @reads_vs_writes = @gets['counts'].collect.with_index{|obj, i| obj.clone << @sets['counts'][i][1] } rescue []
    @hits_vs_misses = @gets['values'].collect.with_index{|obj, i| [obj[0], obj[1].to_f * @gets['counts'][i][1].to_f, (1 - obj[1].to_f) * @gets['counts'][i][1].to_f] } rescue []
    @top_reads = @lm.keys_summaries(@topic, 'get', @resolution, @order, @dir, nil, @step * @count).first(8)
    @top_writes = @lm.keys_summaries(@topic, 'set', @resolution, @order, @dir, nil, @step * @count).first(8)
    render :litecache
  end
  
  def litedb
    @order = 'rcount' unless @order
    @topic = 'Litedb'
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event['name'])
      event['counts'] = data_points.collect{|r| [r['rtime'],r['rcount'] || 0]}
      event['values'] = data_points.collect{|r| [r['rtime'],r['rtotal'] || 0]}
    end
    @snapshot = read_snapshot(@topic)
    @size = @snapshot[0][:summary][:size] rescue 0
    @tables = @snapshot[0][:summary][:tables] rescue 0
    @indexes = @snapshot[0][:summary][:indexes] rescue 0
    @gets = @events.find{|t| t['name'] == 'Read'}
    @sets = @events.find{|t| t['name'] == 'Write'}
    @reads = @gets['rcount'] rescue 0
    @writes = @sets['rcount'] rescue 0
    @time = @gets['ravg'] rescue 0
    @reads_vs_writes = @gets['counts'].collect.with_index{|obj, i| obj.clone << @sets['counts'][i][1] } rescue []
    @reads_vs_writes_times = @gets['values'].collect.with_index{|obj, i| [obj[0], obj[1], @sets['values'][i][1].to_f] } rescue []
    @read_times = @gets['rtotal'] rescue 0
    @write_times = @sets['rtotal'] rescue 0
    @slowest = @lm.keys_summaries(@topic, 'Read', @resolution, 'ravg', 'desc', nil, @step * @count).first(8)
    @slowest += @lm.keys_summaries(@topic, 'Write', @resolution, 'ravg', 'desc', nil, @step * @count).first(8)
    @slowest = @slowest.sort{|a, b| a['ravg'] <=> b['ravg']}.reverse.first(8) 
    @popular = @lm.keys_summaries(@topic, 'Read', @resolution, 'rtotal', 'desc', nil, @step * @count).first(8)
    @popular += @lm.keys_summaries(@topic, 'Write', @resolution, 'rtotal', 'desc', nil, @step * @count).first(8)
    @popular = @popular.sort{|a, b| a['rtotal'] <=> b['rtotal']}.reverse.first(8) 
    render :litedb
  end
  
  def litejob
    @order = 'rcount' unless @order
    @topic = 'Litejob'
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event['name'])
      event['counts'] = data_points.collect{|r| [r['rtime'],r['rcount'] || 0]}
      event['values'] = data_points.collect{|r| [r['rtime'],r['rtotal'] || 0]}
    end
    @snapshot = read_snapshot(@topic)
    @size = @snapshot[0][:summary][:size] rescue 0
    @jobs = @snapshot[0][:summary][:jobs] rescue 0
    @queues = @snapshot[0][:queues] rescue {}
    @processed_jobs = @events.find{|e|e['name'] == 'perform'}
    @processed_count = @processed_jobs['rcount'] rescue 0
    @processing_time = @processed_jobs['rtotal'] rescue 0 
    keys_summaries = @lm.keys_summaries(@topic, 'perform', @resolution, 'rcount', 'desc', nil, @step * @count)
    @processed_count_by_queue = keys_summaries.collect{|r|[r['key'], r['rcount']]}
    @processing_time_by_queue = keys_summaries.collect{|r|[r['key'], r['rtotal']]} #.sort{|r1, r2| r1['rtotal'] > r2['rtotal'] }
    @processed_count_over_time = @events.find{|e| e['name'] == 'perform'}['counts'] rescue []
    @processing_time_over_time = @events.find{|e| e['name'] == 'perform'}['values'] rescue []
    @processed_count_over_time_by_queues = [] 
    @processing_time_over_time_by_queues = []
    keys = ['Time']
    keys_summaries.each_with_index do |summary,i|
      key = summary['key']
      keys << key
      data_points = @lm.key_data_points(@step, @count, @resolution, @topic, 'perform', key)
      if i == 0
        data_points.each do |dp|        
          @processed_count_over_time_by_queues << [dp['rtime']] 
          @processing_time_over_time_by_queues << [dp['rtime']] 
        end
      end
      data_points.each_with_index do |dp, j|
        @processed_count_over_time_by_queues[j] << (dp['rcount'] || 0)
        @processing_time_over_time_by_queues[j] << (dp['rtotal'] || 0)
      end
    end
    @processed_count_over_time_by_queues.unshift(keys)
    @processing_time_over_time_by_queues.unshift(keys)      
    render :litejob
  end
  
  def litecable
    @order = 'rcount' unless @order
    @topic = 'Litecable'
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event['name'])
      event['counts'] = data_points.collect{|r| [r['rtime'],r['rcount'] || 0]}
    end

    @subscription_count = @events.find{|t| t['name'] == 'subscribe'}['rcount'] rescue 0
    @broadcast_count = @events.find{|t| t['name'] == 'broadcast'}['rcount'] rescue 0
    @message_count = @events.find{|t| t['name'] == 'message'}['rcount'] rescue 0

    @subscriptions_over_time = @events.find{|t| t['name'] == 'subscribe'}['counts'] rescue []
    @broadcasts_over_time = @events.find{|t| t['name'] == 'broadcast'}['counts'] rescue []
    @messages_over_time = @events.find{|t| t['name'] == 'message'}['counts'] rescue []
    @messages_over_time = @messages_over_time.collect.with_index{|msg, i| [msg[0], @broadcasts_over_time[i][1], msg[1]]}
    
    @top_subscribed_channels = @lm.keys_summaries(@topic, 'subscribe', @resolution, @order, @dir, @search, @step * @count).first(8)
    @top_messaged_channels = @lm.keys_summaries(@topic, 'message', @resolution, @order, @dir, @search, @step * @count).first(8)
    render :litecable
  end
  
  def index_url
    "/?res=#{@res}&order=#{@order}&dir=#{@dir}&search=#{@search}"
  end
  
  def topic_url(topic)
    "/topics/#{encode(topic)}?res=#{@res}&order=#{@order}&dir=#{@dir}&search=#{@search}"
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
  
  def round(float)
    return 0 unless float.is_a? Numeric
    ((float * 100).round).to_f / 100
  end
  
  def format(float)
    string = float.to_s
    whole, decimal = string.split('.')
    whole = whole.split('').reverse.each_slice(3).map(&:join).join(',').reverse
    whole = [whole, decimal].join('.') if decimal
    whole
  end
  
  def self.app
   @@app
  end

  private
  
  def read_snapshot(topic)
    snapshot = @lm.snapshot(topic)
    if snapshot.empty?
      snapshot = []
    else
      snapshot[0] = Oj.load(snapshot[0]) unless snapshot[0].nil?
    end
    snapshot  
  end
  
  def render(tpl_name)
    layout = Tilt.new("#{__dir__}/views/layout.erb")
    tpl_path = "#{__dir__}/views/#{tpl_name.to_s}.erb"
    tpl = Tilt.new(tpl_path)
    res = layout.render(self){tpl.render(self)}
  end


end




#Rack::Server.start({app: Litebaord.app, daemonize: false})
