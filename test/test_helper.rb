# frozen_string_literal: true

ENV["APP_ENV"] = "test"
ENV["LITEJOB_NO_AUTORUN"] = "1"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "simplecov"
require "timecop"

SimpleCov.start do
  enable_coverage :branch

  add_filter '/test/'
end

require "litestack"
require "lite_job"
require "lite_job/database_connection"

require "minitest/autorun"

Timecop.safe_mode = true

class Performance
  def self.reset!
    @performances = 0
  end

  def self.performed!
    @performances ||= 0
    @performances += 1
  end

  def self.processed!(item, scope: :default)
    @processed_items ||= {}
    @processed_items[scope] ||= []
    @processed_items[scope] << item
  end

  def self.processed_items(scope = :default)
    @processed_items[scope]
  end

  def self.performances
    @performances || 0
  end
end

class LiteTestCase < Minitest::Test
  def setup
    LiteJob::DatabaseConnection.transaction
    LiteJob.configuration.logger = nil
  end

  def teardown
    LiteJob::DatabaseConnection.rollback
    LiteJob.reset!
    ::Performance.reset!
  end
end