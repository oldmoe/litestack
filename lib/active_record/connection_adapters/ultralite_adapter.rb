require_relative './sqlite3_adapter'

module ActiveRecord
	module ConnectionAdapters # :nodoc:

		class UltraliteAdapter < SQLite3Adapter
		  ADAPTER_NAME = "Ultralite"
		end

	end
	
end
