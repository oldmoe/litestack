require 'ultralite'

require "delegate"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/numeric/time"

module ActiveSupport
  module Cache
    class UltraliteCacheStore < Store

      prepend Strategy::LocalCache
		  
      def self.supports_cache_versioning?
        false
      end


      def initialize(path)
      	@cache = ::Ultralite::Cache.new(path, {return_full_record: true})
      end

      def increment(key, amount = 1, options = nil)
        options = merged_options(options)
        @cache.increment(key, amount, options[:expires_in])
      end

      def decrement(key, amount = 1, options = nil)
        options = merged_options(options)
        @cache.decrement(key, amount, options[:expires_in])
      end

      def clear()
      	@cache.clear
      end

      private
        module Coders # :nodoc:
          class << self
            def [](version)
              case version
              when 6.1
                Rails61Coder
              when 7.0
                Rails70Coder
              else
                raise ArgumentError, "Unknown ActiveSupport::Cache.format_version #{Cache.format_version.inspect}"
              end
            end
          end

          module Loader
            def load(payload)
              if payload.is_a?(Entry)
                payload
              else
                Cache::Coders::Loader.load(payload)
              end
            end
          end

          module Rails61Coder
            include Loader
            extend self

            def dump(entry)
              entry
            end

            def dump_compressed(entry, threshold)
              entry.compressed(threshold)
            end
          end

          module Rails70Coder
            include Cache::Coders::Rails70Coder
            include Loader
            extend self
          end
        end

        def default_coder
          Coders[Cache.format_version]
        end

        # Read an entry from the cache.
        def read_entry(key, **options)
          deserialize_entry(read_serialized_entry(key, **options), **options)
        end

        def read_serialized_entry(key, **options)
          record = @cahce.get(key)
        end

        # Write an entry to the cache.
        def write_entry(key, entry, **options)
          write_serialized_entry(key, serialize_entry(entry, **options), **options)
        end

        def write_serialized_entry(key, payload, **options)
          method = options[:unless_exist] ? :add : :set
          expires_in = options[:expires_in].to_i
          if options[:race_condition_ttl] && expires_in > 0 && !options[:raw]
            expires_in += 5.minutes
          end
          options.delete(:compress)
          @data.with { |c| c.send(method, key, payload, expires_in, **options) }
        end

        # Reads multiple entries from the cache implementation.
        def read_multi_entries(names, **options)
          keys_to_names = names.index_by { |name| normalize_key(name, options) }

          raw_values = @data.with { |c| c.get_multi(keys_to_names.keys) }
          values = {}

          raw_values.each do |key, value|
            entry = deserialize_entry(value, raw: options[:raw])

            unless entry.expired? || entry.mismatched?(normalize_version(keys_to_names[key], options))
              values[keys_to_names[key]] = entry.value
            end
          end

          values
        end

        # Delete an entry from the cache.
        def delete_entry(key, **options)
          rescue_error_with(false) { @data.with { |c| c.delete(key) } }
        end

        def serialize_entry(entry, raw: false, **options)
          if raw
            entry.value.to_s
          else
            super(entry, raw: raw, **options)
          end
        end


        def deserialize_entry(payload, raw: false, **)
          if payload && raw
            Entry.new(payload)
          else
            super(payload)
          end
        end

        def rescue_error_with(fallback)
          begin
            yield
          rescue Exception => error
            ActiveSupport.error_reporter&.report(error, handled: true, severity: :warning)
            logger.error("Ultralite (#{error}): #{error.message}") if logger
            fallback
          end
		
        end
    end
  end
end
