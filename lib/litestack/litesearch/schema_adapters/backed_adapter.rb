class Litesearch::Schema::BackedAdapter < Litesearch::Schema::ContentlessAdapter
  private

  def table
    @schema[:table]
  end

  def generate_sql
    super
    @sql[:rebuild] = :rebuild_sql
    @sql[:drop_primary_triggers] = :drop_primary_triggers_sql
    @sql[:drop_secondary_triggers] = :drop_secondary_triggers_sql
    @sql[:create_primary_triggers] = :create_primary_triggers_sql
    @sql[:create_secondary_triggers] = :create_secondary_triggers_sql
  end

  def drop_primary_triggers_sql
    <<~SQL
      DROP TRIGGER IF EXISTS #{name}_insert;
      DROP TRIGGER IF EXISTS #{name}_update;
      DROP TRIGGER IF EXISTS #{name}_update_not;
      DROP TRIGGER IF EXISTS #{name}_delete;
    SQL
  end

  def create_primary_triggers_sql(active = false)
    when_stmt = "TRUE"
    cols = active_cols_names
    if (filter = @schema[:filter_column])
      when_stmt = "NEW.#{filter} = TRUE"
      cols << filter
    end

    <<-SQL
  CREATE TRIGGER #{name}_insert AFTER INSERT ON #{table} WHEN #{when_stmt} BEGIN
    INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) VALUES (NEW.rowid, #{trigger_cols_sql});
  END;
  CREATE TRIGGER #{name}_update AFTER UPDATE OF #{cols.join(", ")} ON #{table} WHEN #{when_stmt} BEGIN
    INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) VALUES (NEW.rowid, #{trigger_cols_sql});
  END;
  CREATE TRIGGER #{name}_update_not AFTER UPDATE OF #{cols.join(", ")} ON #{table} WHEN NOT #{when_stmt} BEGIN
    DELETE FROM #{name} WHERE rowid = NEW.rowid;
  END;
  CREATE TRIGGER #{name}_delete AFTER DELETE ON #{table} BEGIN
    DELETE FROM #{name} WHERE rowid = OLD.id;
  END;
    SQL
  end

  def drop_secondary_trigger_sql(target_table, target_col, col)
    "DROP TRIGGER IF EXISTS #{target_table}_#{target_col}_#{col}_#{name}_update;"
  end

  def create_secondary_trigger_sql(target_table, target_col, col)
    <<~SQL
      CREATE TRIGGER #{target_table}_#{target_col}_#{col}_#{name}_update AFTER UPDATE OF #{target_col} ON #{target_table} BEGIN
        #{rebuild_sql} AND #{table}.#{col} = NEW.id;
      END;
    SQL
  end

  def drop_secondary_triggers_sql
    sql = ""
    @schema[:fields].each do |name, field|
      if field[:trigger_sql]
        sql << drop_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col])
      end
    end
    sql.empty? ? nil : sql
  end

  def create_secondary_triggers_sql
    sql = ""
    @schema[:fields].each do |name, field|
      if field[:trigger_sql]
        sql << create_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col])
      end
    end
    sql.empty? ? nil : sql
  end

  def rebuild_sql
    conditions = ""
    jcs = join_conditions_sql
    fs = filter_sql
    conditions = " ON #{jcs} #{fs}" unless jcs.empty? && fs.empty?
    "INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) SELECT #{table}.id, #{select_cols_sql} FROM #{join_tables_sql} #{conditions}"
  end

  def enrich_schema
    @schema[:fields].each do |name, field|
      if field[:target] && !field[:target].start_with?("#{table}.")
        field[:target] = field[:target].downcase
        target_table, target_col = field[:target].split(".")
        field[:col] = :"#{name}_id" unless field[:col]
        field[:target_table] = target_table.to_sym
        field[:target_col] = target_col.to_sym
        field[:sql] = "(SELECT #{field[:target_col]} FROM #{field[:target_table]} WHERE id = NEW.#{field[:col]})"
        field[:trigger_sql] = true # create_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col])
        field[:target_table_alias] = "#{field[:target_table]}_#{name}"
      else
        field[:col] = name unless field[:col]
        field[:sql] = field[:col]
        field[:target_table] = @schema[:table]
        field[:target] = "#{@schema[:table]}.#{field[:sql]}"
      end
    end
  end

  def filter_sql
    sql = ""
    sql << " AND #{@schema[:filter_column]} = TRUE " if @schema[:filter_column]
    sql
  end

  def trigger_cols_sql
    active_fields.collect do |name, field|
      field[:trigger_sql] ? field[:sql] : "NEW.#{field[:sql]}"
    end.join(", ")
  end

  def select_cols_sql
    active_fields.collect do |name, field|
      (!field[:trigger_sql].nil?) ? "#{field[:target_table_alias]}.#{field[:target_col]}" : field[:target]
    end.join(", ")
  end

  def join_tables_sql
    tables = [@schema[:table]]
    active_fields.each do |name, field|
      tables << "#{field[:target_table]} AS #{field[:target_table_alias]}" if field[:trigger_sql]
    end
    tables.uniq.join(", ")
  end

  def join_conditions_sql
    conditions = []
    active_fields.each do |name, field|
      conditions << "#{field[:target_table_alias]}.id = #{@schema[:table]}.#{field[:col]}" if field[:trigger_sql]
    end
    conditions.join(" AND ")
  end
end
