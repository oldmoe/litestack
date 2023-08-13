# frozen_stringe_literal: true

require_relative '../../litestack/litecable'

module ActionCable
  module SubscriptionAdapter
    class Litecable < ::Litecable# :nodoc:

      attr_reader :logger, :server
      
      prepend ChannelPrefix

      def initialize(server, logger=nil)
        @server = server
        @logger = server.logger
        super({config_path: "./config/litecable.yml"})
      end
            
      def shutdown
        close
      end
    
    end
  end
end

