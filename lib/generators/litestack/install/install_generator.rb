class Litestack::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  # Force copy configuration files so Rails installs don't ask questions
  # that less experienced people might not understand. The more Sr folks.
  # will know to check git to look at what changed.
  def modify_database_adapter
    copy_file "database.yml", "config/database.yml", force: true
  end

  def modify_action_cable_adapter
    copy_file "cable.yml", "config/cable.yml", force: true
  end

  def modify_cache_store_adapter
    gsub_file "config/environments/production.rb",
      "# config.cache_store = :mem_cache_store",
      "config.cache_store = :litecache"
  end

  def modify_active_job_adapter
    gsub_file "config/environments/production.rb",
      "# config.active_job.queue_adapter     = :resque",
      "config.active_job.queue_adapter = :litejob"
  end

  def modify_gitignore
    append_file ".gitignore", <<~TEXT

      # Ignore default Litestack SQLite databases.
      /db/**/*.sqlite3
      /db/**/*.sqlite3-*
    TEXT
  end
end
