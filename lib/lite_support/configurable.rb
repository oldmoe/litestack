require 'yaml'
require_relative "configuration"

module LiteSupport
  # The LiteSupport::Configurable module offers a flexible way to add configuration functionality to any Ruby class/module.
  # It provides a set of class methods to manage configurations such as setting default values, loading configurations
  # from a YAML file, customizing configurations through a DSL-style block, and resetting configurations to defaults.
  #
  # Example Usage:
  # ---------------
  # class MyClass
  #   include LiteSupport::Configurable
  #
  #   # Set default configurations
  #   self.default_configuration = { host: "localhost", port: 3000 }
  # end
  #
  # # Configure using a block
  # MyClass.configure do |config|
  #   config.host = "example.com"
  #   config.port = 8080
  # end
  #
  # # Load configurations from a YAML file
  # MyClass.configures_from("path/to/config.yml")
  #
  # # Access the configuration
  # puts MyClass.configuration.host # => "example.com"
  # puts MyClass.configuration.port # => 8080
  #
  # # Reset configuration to defaults
  # MyClass.reset_configuration!
  # puts MyClass.configuration.host # => "localhost"
  # puts MyClass.configuration.port # => 3000
  module Configurable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def configure
        yield(configuration) if block_given?
      end

      def configures_from(file_path)
        configuration.load_yaml(file_path)
      end

      def default_configuration=(defaults)
        @defaults = defaults
        @configuration = Configuration.new(defaults)
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def reset_configuration!
        @configuration = Configuration.new(@defaults)
      end
    end
  end
end