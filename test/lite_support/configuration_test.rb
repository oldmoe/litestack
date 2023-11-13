require_relative "../test_helper"
require 'minitest/autorun'
require "lite_support/configuration"
require 'tempfile'

class ConfigurationTest < Minitest::Test
  def setup
    @defaults = { name: "Test", value: 42 }
    @config = LiteSupport::Configuration.new(@defaults)
  end

  def test_initialize_with_defaults
    assert_equal "Test", @config.name
    assert_equal 42, @config.value
  end

  def test_load_yaml_with_valid_file
    Tempfile.create(['config', '.yml']) do |file|
      file.write({ name: "Updated", new_key: "New Value" }.to_yaml)
      file.rewind

      @config.load_yaml(file.path)

      assert_equal "Updated", @config.name
      assert_equal "New Value", @config.new_key
      assert_equal 42, @config.value # Ensure original default value is still present
    end
  end

  def test_load_yaml_with_nonexistent_file
    @config.load_yaml("nonexistent_file.yml")
    assert_equal "Test", @config.name
    assert_equal 42, @config.value
  end

  def test_dynamic_method_assignment
    @config.new_setting = "New Setting Value"
    assert_equal "New Setting Value", @config.new_setting
  end

  def test_dynamic_method_retrieval
    assert_nil @config.undefined_method
  end

  def test_respond_to_missing
    assert @config.respond_to?(:any_random_method)
  end
end
