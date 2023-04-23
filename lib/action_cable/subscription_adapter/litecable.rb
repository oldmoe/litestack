# frozen_stringe_literal: true

require_relative '../../litestack/litecable'

module ActionCable
  module SubscriptionAdapter
    class Litecable < ::Litecable# :nodoc:

      attr_reader :logger, :server
      
      prepend ChannelPrefix

      DEFAULT_OPTIONS = {
        config_path: "./config/litecable.yml",
        path: "./db/cable.db",
        sync: 0, # no need to sync at all
        mmap_size: 16 * 1024 * 1024, # 16MB of memory hold hot messages
        expire_after: 10, # remove messages older than 10 seconds
        listen_interval: 0.005, # check new messages every 5 milliseconds
        metrics: false
      }

      def initialize(server, logger=nil)
        @server = server
        @logger = server.logger
        super(DEFAULT_OPTIONS.dup)
      end
            
      def shutdown
        close
      end
    
    end
  end
end

