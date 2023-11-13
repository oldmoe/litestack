module LiteSupport
  require 'yaml'

  # The Configuration class is a flexible and dynamic configuration manager
  # for Ruby applications. It provides an easy way to manage and access configuration
  # settings, allowing the loading of settings from YAML files and the ability to
  # set and retrieve configuration options using method-like syntax.
  #
  # Example Usage:
  #   config = LiteSupport::Configuration.new(defaults: {foo: 'bar'})
  #   config.load_yaml('path/to/config.yml')
  #   config.foo # => 'bar'
  #   config.foo = 'new value'
  #   config.foo # => 'new value'
  class Configuration
    def initialize(defaults = {})
      @config = defaults.dup
    end

    def load_yaml(file_path)
      if File.exist?(file_path)
        config_from_file = YAML.load_file(file_path)
        @config.merge!(config_from_file) if config_from_file.is_a?(Hash)
      end
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s.end_with?('=')
        key = method_name.to_s.chomp('=').to_sym
        @config[key] = args.first
      else
        @config.fetch(method_name, nil)
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
end