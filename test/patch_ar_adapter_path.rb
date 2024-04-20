# don't attempt to load the adapter to avoid requiring the gem to be installed
# we can just require the adapter manually
class ActiveRecord::ConnectionAdapters::ConnectionHandler
  def resolve_pool_config(config, connection_name, role, shard)
    db_config = ActiveRecord::Base.configurations.resolve(config)
    ActiveRecord::ConnectionAdapters::PoolConfig.new(connection_name, db_config, role, shard)
  end
end
