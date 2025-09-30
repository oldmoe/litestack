# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"

# Load Rails + AR Railtie so app.config.active_record exists
require "rails"
require "active_record/railtie"

# Load the gem under test (ensures Litestack::Railtie is defined)
require "litestack"

class RailtieTest < Minitest::Test
  class DummyApp < Rails::Application
    # Keep noise down during initialize!
    config.logger = Logger.new(nil)
    config.eager_load = false
    config.secret_key_base = "test"

    # Use Rails defaults that match the current AR when changes were made
    ar_ver = Gem::Version.new(ActiveRecord.version)
    defaults = ar_ver >= Gem::Version.new("8.0.0") ? "8.0" : "7.1"
    config.load_defaults defaults
  end

  def test_litestack_railtie_handles_sqlite3_warning_across_rails_versions
    # Boot the app — this runs all Railtie initializers including litestack’s
    DummyApp.initialize!

    keys = DummyApp.config.active_record.respond_to?(:keys) ? DummyApp.config.active_record.keys : []

    if Gem::Version.new(ActiveRecord.version) >= Gem::Version.new("8.0.0")
      # Rails 8+: key must not be present (writer removed in AR 8)
      refute_includes keys, :sqlite3_production_warning
    else
      # Rails < 8: litestack should still disable the warning
      assert_equal false, DummyApp.config.active_record[:sqlite3_production_warning]
    end
  ensure
    # Clean up so other tests (if any) can re-init safely
    Rails.application = nil
  end
end
