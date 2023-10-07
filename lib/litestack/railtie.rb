require "rails/railtie"

module Litestack
  class Railtie < ::Rails::Railtie
    # The whole point of this gem is to use sqlite3 in production.
    initializer "litestack.disable_sqlite3_production_warning" do |app|
      app.config.active_record.sqlite3_production_warning = false
    end
    
    # Enhance the SQLite3 ActiveRecord adapter with optimized defaults
    initializer "litestack.patch_active_record_sqlite3adapter" do |app|
      ActiveSupport.on_load(:active_record_sqlite3adapter) do
        # self refers to `SQLite3Adapter` here,
        # so we can call .prepend
        prepend ActiveRecord::Patches::SQLite3Adapter
      end
    end
  end
end