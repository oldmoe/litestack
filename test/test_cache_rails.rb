require "minitest/autorun"
require_relative "../lib/active_support/cache/litecache"

class TestCacheRails < Minitest::Test
  def setup
    @cache = ActiveSupport::Cache::Litecache.new({path: ":memory:", sleep_interval: 1})
    @cache.clear
  end

  def test_caceh_write
    @cache.write("key", "value")
    assert_equal "value", @cache.read("key")
    @cache.write("key", "new_value")
    assert_equal "new_value", @cache.read("key")
  end

  def test_cache_fetch
    result = @cache.fetch("key") { "value" }
    assert_equal "value", result
    result = @cache.fetch("key") { "new_value" }
    assert_equal "value", result
  end

  def test_cache_write_multi
    data = {k1: "v1", k2: "v2", k3: "v3"}
    @cache.write_multi(data)
    data.keys.each do |key|
      assert_equal data[key], @cache.read(key)
    end
  end

  def test_cache_read_multi
    data = {k1: "v1", k2: "v2", k3: "v3"}
    data.each_pair { |k, v| @cache.write(k, v) }
    results = @cache.read_multi(*data.keys)
    assert_equal data, results
  end

  def test_cache_write_read_multi
    data = {k1: "v1", k2: "v2", k3: "v3"}
    @cache.write_multi(data)
    results = @cache.read_multi(*data.keys)
    assert_equal data, results
  end

  def test_cache_expiry
    @cache.write("key", "value", expires_at: 1.second.from_now)
    assert_equal "value", @cache.read("key")
    sleep 1.1
    assert_nil @cache.read("key")
  end

  def test_increment_decrement
    @cache.increment("key")
    assert_equal 1, @cache.read("key")
    @cache.increment("key", 5)
    assert_equal 6, @cache.read("key")
    @cache.decrement("key", 4)
    assert_equal 2, @cache.read("key")
  end

  def test_increment_decrement_expiry
    @cache.increment("key", 2, expires_at: 1.second.from_now)
    assert_equal 2, @cache.read("key")
    sleep 1.1
    @cache.increment("key", 5)
    assert_equal 5, @cache.read("key")
  end
end
