require 'minitest/autorun'
require_relative "../test_helper"
require 'lite_support/configurable'
require 'tempfile'

class ConfigurableTest < Minitest::Test
  class DummyClass
    include LiteSupport::Configurable
  end

  def setup
    @dummy_class = DummyClass
    @defaults = { default_key: 'default_value' }
    @dummy_class.default_configuration = @defaults
  end

  def test_configuration_inclusion
    assert @dummy_class.respond_to?(:configure)
    assert @dummy_class.respond_to?(:configures_from)
    assert @dummy_class.respond_to?(:configuration)
  end

  def test_default_configuration
    assert_equal 'default_value', @dummy_class.configuration.default_key
  end

  def test_configure
    @dummy_class.configure do |config|
      config.new_key = 'new_value'
    end

    assert_equal 'new_value', @dummy_class.configuration.new_key
  end

  def test_configures_from_with_valid_file
    Tempfile.create(['config', '.yml']) do |file|
      file.write({ new_file_key: 'file_value' }.to_yaml)
      file.rewind

      @dummy_class.configures_from(file.path)

      assert_equal 'file_value', @dummy_class.configuration.new_file_key
      assert_equal 'default_value', @dummy_class.configuration.default_key # Default value still present
    end
  end

  def test_configures_from_with_nonexistent_file
    @dummy_class.configures_from("nonexistent_file.yml")
    assert_equal 'default_value', @dummy_class.configuration.default_key
  end
end
