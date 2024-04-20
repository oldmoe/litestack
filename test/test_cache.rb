require "minitest/autorun"
require_relative "../lib/litestack/litecache"

class TestCache < Minitest::Test
  def setup
    @cache = ::Litecache.new({path: ":memory:", sleep_interval: 1})
    @cache.clear
  end

  def test_cache_set
    @cache.set("key", "value")
    assert_equal "value", @cache.get("key")
    @cache.set("key", "new_value")
    assert_equal "new_value", @cache.get("key")
  end

  def test_cache_set_unless_exists
    @cache.set("key", "value")
    assert_equal "value", @cache.get("key")
    @cache.set_unless_exists("key", "new_value")
    assert_equal "value", @cache.get("key")
  end

  def test_cache_set_multi
    data = {k1: "v1", k2: "v2", k3: "v3"}
    @cache.set_multi(data)
    data.keys.each do |key|
      assert_equal data[key], @cache.get(key)
    end
  end

  def test_cache_get_multi
    data = {k1: "v1", k2: "v2", k3: "v3"}
    data.each_pair { |k, v| @cache.set(k, v) }
    results = @cache.get_multi(*data.keys)
    assert_equal data, results
  end

  def test_cache_expiry
    @cache.set("key", "value", 1)
    assert_equal "value", @cache.get("key")
    sleep 1.1
    assert_nil @cache.get("key")
  end

  def test_increment_decrement
    @cache.increment("key")
    assert_equal 1, @cache.get("key")
    @cache.increment("key", 5)
    assert_equal 6, @cache.get("key")
    @cache.decrement("key", 4)
    assert_equal 2, @cache.get("key")
  end

  def test_increment_decrement_expiry
    @cache.increment("key", 2, 1)
    assert_equal 2, @cache.get("key")
    sleep 1.1
    @cache.increment("key", 5)
    assert_equal 5, @cache.get("key")
  end
end
