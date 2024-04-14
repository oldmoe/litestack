require "rails/railtie"

module Litestack
  class Railtie < ::Rails::Railtie
    if config.active_record.key?(:sqlite3_production_warning)
      initializer :disable_production_sqlite_warning do |app|
        # The whole point of this gem is to use sqlite3 in production.
        app.config.active_record.sqlite3_production_warning = false
      end
    end
  end
end
