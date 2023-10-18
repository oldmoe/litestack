# frozen_string_literal: true

require "active_support/cache"
require "active_support/test_case"
# require_relative "../lib/active_support/cache/ultralite_cache_store"
require "active_support/cache/ultralite_cache_store"

require "minitest/autorun"
require "sqlite3"
LARGE_STRING = "A" * 2048
LARGE_OBJECT = ["A"] * 2048
class UltraliteCacheStoreTest < ActiveSupport::TestCase
  def setup
    @cache = lookup_store(expires_in: 60)
  end

  def lookup_store(options = {})
    ActiveSupport::Cache.lookup_store(:ultralite_cache_store, options)
  end

  #  def test_large_string_with_default_compression_settings
  #    assert_uncompressed(LARGE_STRING)
  #  end

  # def test_large_object_with_default_compression_settings
  #    assert_uncompressed(LARGE_OBJECT)
  #  end
  def test_increment_preserves_expiry
    @cache = lookup_store
    @cache.write("counter", 1, raw: true, expires_in: 1.seconds)
    assert_equal 1, @cache.read("counter", raw: true)
    sleep 2
    assert_nil @cache.read("counter", raw: true)

    @cache.write("counter", 1, raw: true, expires_in: 1.seconds)
    @cache.increment("counter", 1, expires_in: 1)
    assert_equal 2, @cache.read("counter", raw: true)
    sleep 2
    assert_nil @cache.read("counter", raw: true)
  end
end

class UltraliteStorePruningTest < ActiveSupport::TestCase
  def setup
    @record_size = 10
    @cache = ActiveSupport::Cache.lookup_store(:ultralite_cache_store, expires_in: 60, size: 1)
    @cache.clear
    @db = SQLite3::Database.new(":memory:")
  end

  def test_prune_all
    128.times do |i|
      @cache.write(i, @db.get_first_value("select hex(randomblob(1024*4))")) && sleep(0.001)
    end
    assert_not_equal(@cache.count, 128)
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
    item = {"foo" => "bar"}
    key = "test_key"
    @cache.write(key, item)
    read_item = @cache.read(key)
    read_item["foo"] = "xyz"
    assert_equal item, @cache.read(key)
  end

  def test_cache_different_object_ids_hash
    item = {"foo" => "bar"}
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
    # #travel 2.seconds
    sleep 2
    assert_equal true, @cache.write(1, "bbbb", expires_in: 1.second, unless_exist: true)
  end
end
