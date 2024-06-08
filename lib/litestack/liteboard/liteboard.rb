# frozen_string_literal: true

require "rack"
require "tilt"
require "erubi"

# require relative so we pick the gem version that corresponds to the liteboard binary
require_relative "../../litestack/litemetric"

class Liteboard
  @@resolutions = {"minute" => [300, 12], "hour" => [3600, 24], "day" => [3600 * 24, 7], "week" => [3600 * 24 * 7, 53], "year" => [3600 * 24 * 365, 100]}
  @@res_mapping = {"hour" => "minute", "day" => "hour", "week" => "day", "year" => "week"}
  @@templates = {}
  @@app = proc do |env|
    case env["PATH_INFO"]
    when "/"
      Liteboard.new(env).call(:index)
    when "/topics/Litejob"
      Liteboard.new(env).call(:litejob)
    when "/topics/Litecache"
      Liteboard.new(env).call(:litecache)
    when "/topics/Litedb"
      Liteboard.new(env).call(:litedb)
    when "/topics/Litecable"
      Liteboard.new(env).call(:litecable)
    end
  end

  def initialize(env)
    @env = env
    @req = Rack::Request.new(@env)
    @params = @req.params
    @running = true
    @lm = Litemetric.instance
  end

  def params(key)
    URI.decode_uri_component(@params[key.to_s].to_s)
  end

  def call(method)
    before
    res = send(method)
    after(res)
  end

  def after(body = nil)
    [200, {"Cache-Control" => "no-cache"}, [body]]
  end

  def before
    @res = params(:res) || "day"
    @resolution = @@res_mapping[@res]
    if !@resolution
      @res = "day"
      @resolution = @@res_mapping[@res]
    end
    @step = @@resolutions[@resolution][0]
    @count = @@resolutions[@resolution][1]
    @order = params(:order)
    @order = nil if @order == ""
    @dir = params(:dir)
    @dir = "desc" if @dir.nil? || @dir == ""
    @dir = @dir.downcase
    @idir = if @dir == "asc"
      "desc"
    else
      "asc"
    end
    @search = params(:search)
    @search = nil if @search == ""
    @topics = @lm.topic_summaries(@resolution, @step * @count, @order, @dir, @search)
  end

  def index
    @order ||= "topic"
    @topics.each do |topic|
      data_points = @lm.topic_data_points(@step, @count, @resolution, topic[0])
      topic << data_points.collect { |r| [r[0], r[2] || 0] }
    end
    render :index
  end

  def litecache
    @order ||= "rcount"
    @topic = "Litecache"
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event["name"])
      event["counts"] = data_points.collect { |r| [r["rtime"], r["rcount"]] }
      event["values"] = data_points.collect { |r| [r["rtime"], r["ravg"]] }
    end
    @snapshot = read_snapshot(@topic)
    @size = begin
      @snapshot[0][:summary][:size]
    rescue
      0
    end
    @max_size = begin
      @snapshot[0][:summary][:max_size]
    rescue
      0
    end
    @full = begin
      (@size / @max_size) * 100
    rescue
      0
    end
    @entries = begin
      @snapshot[0][:summary][:entries]
    rescue
      0
    end
    @gets = @events.find { |t| t["name"] == "get" }
    @sets = @events.find { |t| t["name"] == "set" }
    @reads = begin
      @gets["rcount"]
    rescue
      0
    end
    @writes = begin
      @sets["rcount"]
    rescue
      0
    end
    @hitrate = begin
      @gets["ravg"]
    rescue
      0
    end
    @hits = @reads * @hitrate
    @misses = @reads - @hits
    @reads_vs_writes = begin
      @gets["counts"].collect.with_index { |obj, i| obj.clone << @sets["counts"][i][1] }
    rescue
      []
    end
    @hits_vs_misses = begin
      @gets["values"].collect.with_index { |obj, i| [obj[0], obj[1].to_f * @gets["counts"][i][1].to_f, (1 - obj[1].to_f) * @gets["counts"][i][1].to_f] }
    rescue
      []
    end
    @top_reads = @lm.keys_summaries(@topic, "get", @resolution, @order, @dir, nil, @step * @count).first(8)
    @top_writes = @lm.keys_summaries(@topic, "set", @resolution, @order, @dir, nil, @step * @count).first(8)
    render :litecache
  end

  def litedb
    @order ||= "rcount"
    @topic = "Litedb"
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event["name"])
      event["counts"] = data_points.collect { |r| [r["rtime"], r["rcount"] || 0] }
      event["values"] = data_points.collect { |r| [r["rtime"], r["rtotal"] || 0] }
    end
    @snapshot = read_snapshot(@topic)
    @size = begin
      @snapshot[0][:summary][:size]
    rescue
      0
    end
    @tables = begin
      @snapshot[0][:summary][:tables]
    rescue
      0
    end
    @indexes = begin
      @snapshot[0][:summary][:indexes]
    rescue
      0
    end
    @gets = @events.find { |t| t["name"] == "Read" }
    @sets = @events.find { |t| t["name"] == "Write" }
    @reads = begin
      @gets["rcount"]
    rescue
      0
    end
    @writes = begin
      @sets["rcount"]
    rescue
      0
    end
    @time = begin
      @gets["ravg"]
    rescue
      0
    end
    @reads_vs_writes = begin
      @gets["counts"].collect.with_index { |obj, i| obj.clone << @sets["counts"][i][1] }
    rescue
      []
    end
    @reads_vs_writes_times = begin
      @gets["values"].collect.with_index { |obj, i| [obj[0], obj[1], @sets["values"][i][1].to_f] }
    rescue
      []
    end
    @read_times = begin
      @gets["rtotal"]
    rescue
      0
    end
    @write_times = begin
      @sets["rtotal"]
    rescue
      0
    end
    @slowest = @lm.keys_summaries(@topic, "Read", @resolution, "ravg", "desc", nil, @step * @count).first(8)
    @slowest += @lm.keys_summaries(@topic, "Write", @resolution, "ravg", "desc", nil, @step * @count).first(8)
    @slowest = @slowest.sort_by { |a| a["ravg"] }.last(8).reverse
    @popular = @lm.keys_summaries(@topic, "Read", @resolution, "rtotal", "desc", nil, @step * @count).first(8)
    @popular += @lm.keys_summaries(@topic, "Write", @resolution, "rtotal", "desc", nil, @step * @count).first(8)
    @popular = @popular.sort_by { |a| a["rtotal"] }.last(8).reverse
    render :litedb
  end

  def litejob
    @order ||= "rcount"
    @topic = "Litejob"
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event[:name])
      event["counts"] = data_points.collect { |r| [r["rtime"], r["rcount"] || 0] }
      event["values"] = data_points.collect { |r| [r["rtime"], r["rtotal"] || 0.0] }
    end
    @snapshot = read_snapshot(@topic)
    @size = begin
      @snapshot[0][:summary][:size]
    rescue
      0
    end
    @jobs = begin
      @snapshot[0][:summary][:jobs]
    rescue
      0
    end
    @queues = begin
      @snapshot[0][:queues]
    rescue
      {}
    end
    @processed_jobs = @events.find { |e| e["name"] == "perform" }
    @processed_count = begin
      @processed_jobs["rcount"]
    rescue
      0
    end
    @processing_time = begin
      @processed_jobs["rtotal"]
    rescue
      0
    end
    keys_summaries = @lm.keys_summaries(@topic, "perform", @resolution, "rcount", "desc", nil, @step * @count)
    @processed_count_by_queue = keys_summaries.collect { |r| [r["key"], r["rcount"]] }
    @processing_time_by_queue = keys_summaries.collect { |r| [r["key"], r["rtotal"]] } # .sort{|r1, r2| r1['rtotal'] > r2['rtotal'] }
    @processed_count_over_time = begin
      @events.find { |e| e["name"] == "perform" }["counts"]
    rescue
      []
    end
    @processing_time_over_time = begin
      @events.find { |e| e["name"] == "perform" }["values"]
    rescue
      []
    end
    @processed_count_over_time_by_queues = []
    @processing_time_over_time_by_queues = []
    keys = ["Time"]
    keys_summaries.each_with_index do |summary, i|
      key = summary["key"]
      keys << key
      data_points = @lm.key_data_points(@step, @count, @resolution, @topic, "perform", key)
      if i == 0
        data_points.each do |dp|
          @processed_count_over_time_by_queues << [dp["rtime"]]
          @processing_time_over_time_by_queues << [dp["rtime"]]
        end
      end
      data_points.each_with_index do |dp, j|
        @processed_count_over_time_by_queues[j] << (dp["rcount"] || 0)
        @processing_time_over_time_by_queues[j] << (dp["rtotal"] || 0)
      end
    end
    @processed_count_over_time_by_queues.unshift(keys)
    @processing_time_over_time_by_queues.unshift(keys)
    render :litejob
  end

  def litecable
    @order ||= "rcount"
    @topic = "Litecable"
    @events = @lm.events_summaries(@topic, @resolution, @order, @dir, @search, @step * @count)
    @events.each do |event|
      data_points = @lm.event_data_points(@step, @count, @resolution, @topic, event["name"])
      event["counts"] = data_points.collect { |r| [r["rtime"], r["rcount"] || 0] }
    end

    @subscription_count = begin
      @events.find { |t| t["name"] == "subscribe" }["rcount"]
    rescue
      0
    end
    @broadcast_count = begin
      @events.find { |t| t["name"] == "broadcast" }["rcount"]
    rescue
      0
    end
    @message_count = begin
      @events.find { |t| t["name"] == "message" }["rcount"]
    rescue
      0
    end

    @subscriptions_over_time = begin
      @events.find { |t| t["name"] == "subscribe" }["counts"]
    rescue
      []
    end
    @broadcasts_over_time = begin
      @events.find { |t| t["name"] == "broadcast" }["counts"]
    rescue
      []
    end
    @messages_over_time = begin
      @events.find { |t| t["name"] == "message" }["counts"]
    rescue
      []
    end
    @messages_over_time = @messages_over_time.collect.with_index { |msg, i| [msg[0], @broadcasts_over_time[i][1], msg[1]] }

    @top_subscribed_channels = @lm.keys_summaries(@topic, "subscribe", @resolution, @order, @dir, @search, @step * @count).first(8)
    @top_messaged_channels = @lm.keys_summaries(@topic, "message", @resolution, @order, @dir, @search, @step * @count).first(8)
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
    "res=#{@res}&order=#{field}&dir=#{(@order == field) ? @idir : @dir}&search=#{@search}"
  end

  def sorted?(field)
    @order == field
  end

  def dir(field)
    if sorted?(field)
      if @dir == "asc"
        return "<span class='material-icons'>arrow_drop_up</span>"
      else
        return "<span class='material-icons'>arrow_drop_down</span>"
      end
    end
    "&nbsp;&nbsp;"
  end

  def encode(text)
    URI.encode_uri_component(text)
  end

  def round(float)
    return 0 unless float.is_a? Numeric
    (float * 100).round.to_f / 100
  end

  def format(float)
    float = float.round(3)
    string = float.to_s
    whole, decimal = string.split(".")
    whole = whole.chars.reverse.each_slice(3).map(&:join).join(",").reverse
    whole = [whole, decimal].join(".") if decimal
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
    tpl_path = "#{__dir__}/views/#{tpl_name}.erb"
    tpl = Tilt.new(tpl_path)
    layout.render(self) { tpl.render(self) }
  end
end

# Rack::Server.start({app: Litebaord.app, daemonize: false})
