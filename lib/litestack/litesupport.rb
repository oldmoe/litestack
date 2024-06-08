# frozen_stringe_literal: true

require "sqlite3"
require "logger"
require "oj"
require "yaml"
require "pathname"
require "fileutils"
require "erb"

require_relative "litescheduler"
require_relative "liteconnection"

module Litesupport
  class Error < StandardError; end

  # Detect the Rack or Rails environment.
  def self.detect_environment
    if defined?(Rails) && Rails.respond_to?(:env)
      Rails.env
    elsif ENV["RACK_ENV"]
      ENV["RACK_ENV"]
    elsif ENV["APP_ENV"]
      ENV["APP_ENV"]
    else
      "development"
    end
  end

  def self.environment
    @environment ||= detect_environment
  end

  # Databases will be stored by default at this path.
  def self.root(env = Litesupport.environment)
    ensure_root_volume detect_root(env)
  end

  # Default path where we'll store all of the databases.
  def self.detect_root(env)
    path = if ENV["LITESTACK_DATA_PATH"]
      ENV["LITESTACK_DATA_PATH"]
    elsif defined? Rails
      "./db"
    else
      "."
    end

    Pathname.new(path).join(env)
  end

  def self.ensure_root_volume(path)
    FileUtils.mkdir_p path unless path.exist?
    path
  end

  class Pool
    def initialize(count, &block)
      @count = count
      @block = block
      @resources = Thread::Queue.new
      @mutex = Litescheduler::Mutex.new
      @count.times do
        resource = @mutex.synchronize { block.call }
        @resources << resource
      end
    end

    def acquire
      result = nil
      resource = @resources.pop
      begin
        result = yield resource
      ensure
        @resources << resource
      end
      result
    end
  end
end
