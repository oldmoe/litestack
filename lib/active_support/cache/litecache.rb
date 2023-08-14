require "delegate"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/numeric/time"
require "active_support/cache"
require_relative "../../litestack"

module ActiveSupport
  module Cache
    class Litecache < Store
      prepend Strategy::LocalCache

      def self.supports_cache_versioning?
        true
      end

      def initialize(options = {})
        super
        @options[:return_full_record] = true
        @cache = ::Litecache.new(@options) # reachout to the outer litecache class
      end

      def increment(key, amount = 1, options = nil)
        key = key.to_s
        options = merged_options(options)
        # todo: fix me
        # this is currently a hack to avoid dealing with Rails cache encoding and decoding
        # @cache.transaction(:immediate) do
        if (value = read(key, options))
          value = value.to_i + amount
          write(key, value, options)
        end
        # end
      end

      def decrement(key, amount = 1, options = nil)
        options = merged_options(options)
        increment(key, -1 * amount, options[:expires_in])
      end

      def prune(limit = nil, time = nil)
        @cache.prune(limit)
      end

      def cleanup(limit = nil, time = nil)
        @cache.prune(limit)
      end

      def clear
        @cache.clear
      end

      def count
        @cache.count
      end

      def size
        @cache.size
      end

      def max_size
        @cache.max_size
      end

      def stats
        @cache.stats
      end

      private

      # Read an entry from the cache.
      def read_entry(key, **options)
        deserialize_entry(@cache.get(key))
      end

      # Write an entry to the cache.
      def write_entry(key, entry, **options)
        write_serialized_entry(key, serialize_entry(entry, **options), **options)
      end

      def write_serialized_entry(key, payload, **options)
        expires_in = options[:expires_in].to_i
        if options[:race_condition_ttl] && expires_in > 0 && !options[:raw]
          expires_in += 5.minutes
        end
        if options[:unless_exist]
          @cache.set_unless_exists(key, payload, expires_in)
        else
          @cache.set(key, payload, expires_in)
        end
      end

      # Delete an entry from the cache.
      def delete_entry(key, **options)
        @cache.delete(key)
      end
    end
  end
end
