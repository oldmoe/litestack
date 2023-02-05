module Rails
  class DBConsole
  
    def start
      ENV["RAILS_ENV"] ||= @options[:environment] || environment
      config = db_config.configuration_hash

      case db_config.adapter
      when /^(jdbc)?mysql/
        args = {
          host: "--host",
          port: "--port",
          socket: "--socket",
          username: "--user",
          encoding: "--default-character-set",
          sslca: "--ssl-ca",
          sslcert: "--ssl-cert",
          sslcapath: "--ssl-capath",
          sslcipher: "--ssl-cipher",
          sslkey: "--ssl-key"
        }.filter_map { |opt, arg| "#{arg}=#{config[opt]}" if config[opt] }

        if config[:password] && @options[:include_password]
          args << "--password=#{config[:password]}"
        elsif config[:password] && !config[:password].to_s.empty?
          args << "-p"
        end

        args << db_config.database

        find_cmd_and_exec(["mysql", "mysql5"], *args)

      when /^postgres|^postgis/
        ENV["PGUSER"]         = config[:username] if config[:username]
        ENV["PGHOST"]         = config[:host] if config[:host]
        ENV["PGPORT"]         = config[:port].to_s if config[:port]
        ENV["PGPASSWORD"]     = config[:password].to_s if config[:password] && @options[:include_password]
        ENV["PGSSLMODE"]      = config[:sslmode].to_s if config[:sslmode]
        ENV["PGSSLCERT"]      = config[:sslcert].to_s if config[:sslcert]
        ENV["PGSSLKEY"]       = config[:sslkey].to_s if config[:sslkey]
        ENV["PGSSLROOTCERT"]  = config[:sslrootcert].to_s if config[:sslrootcert]
        find_cmd_and_exec("psql", db_config.database)

      when "sqlite3", "ultralite"
        args = []

        args << "-#{@options[:mode]}" if @options[:mode]
        args << "-header" if @options[:header]
        args << File.expand_path(db_config.database, Rails.respond_to?(:root) ? Rails.root : nil)

        find_cmd_and_exec("sqlite3", *args)


      when "oracle", "oracle_enhanced"
        logon = ""

        if config[:username]
          logon = config[:username].dup
          logon << "/#{config[:password]}" if config[:password] && @options[:include_password]
          logon << "@#{db_config.database}" if db_config.database
        end

        find_cmd_and_exec("sqlplus", logon)

      when "sqlserver"
        args = []

        args += ["-d", "#{db_config.database}"] if db_config.database
        args += ["-U", "#{config[:username]}"] if config[:username]
        args += ["-P", "#{config[:password]}"] if config[:password]

        if config[:host]
          host_arg = +"tcp:#{config[:host]}"
          host_arg << ",#{config[:port]}" if config[:port]
          args += ["-S", host_arg]
        end

        find_cmd_and_exec("sqlcmd", *args)

      else
        abort "Unknown command-line client for #{db_config.database}."
      end
    end
                                                                                                                                                                                           

  end
end
