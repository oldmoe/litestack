module Rails
  class DBConsole
  
    def db_config
      return @db_config if defined?(@db_config)

      # If the user provided a database, use that. Otherwise find
      # the first config in the database.yml
      if database
        @db_config = configurations.configs_for(env_name: environment, name: database, include_hidden: true)
      else
        @db_config = configurations.find_db_config(environment)
      end

      unless @db_config
        missing_db = database ? "'#{database}' database is not" : "No databases are"
        raise ActiveRecord::AdapterNotSpecified,
          "#{missing_db} configured for '#{environment}'. Available configuration: #{configurations.inspect}"
      end
      @db_config.adapter = 'sqlite3' if @db_config.adapter == 'ultralite'
      @db_config
    end
  end
end
