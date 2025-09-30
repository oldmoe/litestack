# lib/litestack/railtie.rb
require "rails/railtie"

module Litestack
  class Railtie < ::Rails::Railtie
    # Ensure we run before Active Record reads/apply its configuration
    initializer :disable_production_sqlite_warning, before: "active_record.set_configs" do |app|
      ar = app.config.active_record

      # Defensive: some older Rails defaults / templates inject this key
      # Rails 8 removed the writer, so delete the key entirely on 8+.
      begin
        require "active_record"
        rails8_or_newer =
          defined?(ActiveRecord::VERSION) &&
          Gem::Version.new(ActiveRecord::VERSION::STRING) >= Gem::Version.new("8.0.0")
      rescue LoadError
        rails8_or_newer = false
      end

      if rails8_or_newer
        # On Rails 8+, nuke the unsupported key if present
        ar.delete(:sqlite3_production_warning) if ar.respond_to?(:delete)
      else
        # On Rails 6/7 keep original behavior
        if ar.respond_to?(:sqlite3_production_warning=)
          ar.sqlite3_production_warning = false
        elsif ar.respond_to?(:[]=)
          ar[:sqlite3_production_warning] = false
        end
      end
    end
  end
end
