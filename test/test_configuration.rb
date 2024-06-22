require "minitest/autorun"
require_relative "../lib/litestack/litesupport"

class SampleLiteComponent
  include Litesupport::Liteconnection

  def initialize(options = {})
    init(options)
  end
end

class TestConfiguration < Minitest::Test
  def test_yaml_with_no_erb
    config_file = Tempfile.new(["litecomponent", ".yml"])
    config_file.write('path: ":memory:"')

    config_file.read

    sample_component = SampleLiteComponent.new({config_path: config_file.path})

    assert_equal sample_component.options[:path], ":memory:"

    config_file.close!
  end

  def test_yaml_with_erb
    config_file = Tempfile.new(["litecomponent", ".yml"])
    config_file.write('path: "<%= ":memory:" %>"')

    config_file.read

    sample_component = SampleLiteComponent.new({config_path: config_file.path})

    assert_equal sample_component.options[:path], ":memory:"

    config_file.close!
  end
end
