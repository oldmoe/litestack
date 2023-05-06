# frozen_string_literal: true

require "active_support/cache"
require "active_support/test_case"
require_relative "../lib/active_support/cache/litecache"

require "minitest/autorun"
require "sqlite3"

class LitecachePruningTest < ActiveSupport::TestCase
  def setup
    @record_size = 10 
    @cache = ActiveSupport::Cache::Litecache.new({expires_in: 60, size: 1})
    #@cache = ActiveSupport::Cache.lookup_store(:litecache, expires_in: 60, size: 1)
    @cache.clear
    @db = SQLite3::Database.new(":memory:")
  end

  def test_prune_all
    1024.times do |i|
      @cache.write(i, @db.get_first_value("select hex(randomblob(1024*10*1))")) #&& sleep(0.001)
    end
    assert_not_equal(@cache.count, 1024)
    assert_not @cache.exist?(0)
  end
  
  def test_prune_size
    @cache.write(1, "aaaaaaaaaa") && sleep(0.001)
    @cache.write(2, "bbbbbbbbbb") && sleep(0.001) 
    @cache.write(3, "cccccccccc") && sleep(0.001)
    @cache.write(4, "dddddddddd") && sleep(0.001)
    @cache.write(5, "eeeeeeeeee") && sleep(0.001)
    @cache.read(2) && sleep(0.001)
    @cache.read(4)
    sleep 2
    @cache.prune(2)
    assert @cache.exist?(5)
    assert @cache.exist?(4)
    assert_not @cache.exist?(3), "no entry"
    assert @cache.exist?(2)
    assert_not @cache.exist?(1), "no entry"
  end

  def test_cache_not_mutated
    item = { "foo" => "bar" }
    key = "test_key"
    @cache.write(key, item)
    read_item = @cache.read(key)
    read_item["foo"] = "xyz"
    assert_equal item, @cache.read(key)
  end
  def test_cache_different_object_ids_hash
    item = { "foo" => "bar" }
    key = "test_key"
    @cache.write(key, item)

    read_item = @cache.read(key)
    assert_not_equal item.object_id, read_item.object_id
    assert_not_equal read_item.object_id, @cache.read(key).object_id
  end

  def test_cache_different_object_ids_string
    item = "my_string"
    key = "test_key"
    @cache.write(key, item)

    read_item = @cache.read(key)
    assert_not_equal item.object_id, read_item.object_id
    assert_not_equal read_item.object_id, @cache.read(key).object_id
  end
  def test_write_with_unless_exist
    assert_equal true, @cache.write(1, "aaaaaaaaaa")
    assert_equal false, @cache.write(1, "aaaaaaaaaa", unless_exist: true)
    @cache.write(1, nil)
    assert_equal false, @cache.write(1, "aaaaaaaaaa", unless_exist: true)
  end

  def test_write_expired_value_with_unless_exist
    assert_equal true, @cache.write(1, "aaaa", expires_in: 1.second)
    sleep 2
    assert_equal true, @cache.write(1, "bbbb", expires_in: 1.second, unless_exist: true)
  end
end

