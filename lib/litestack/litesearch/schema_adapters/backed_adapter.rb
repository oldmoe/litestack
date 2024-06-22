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
    cols = active_cols_names.select { |n| !n.nil? }
    if (filter = @schema[:filter_column])
      when_stmt = "NEW.#{filter} = TRUE"
      cols << filter
    end
    update_filter = +""
    if cols.length > 0
      " OF #{cols.join(", ")} "
    end

    <<-SQL
  CREATE TRIGGER #{name}_insert AFTER INSERT ON #{table} WHEN #{when_stmt} BEGIN
    INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) VALUES (NEW.rowid, #{trigger_cols_sql});
  END;
  CREATE TRIGGER #{name}_update AFTER UPDATE #{update_filter} ON #{table} WHEN #{when_stmt} BEGIN
    INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) VALUES (NEW.rowid, #{trigger_cols_sql});
  END;
  CREATE TRIGGER #{name}_update_not AFTER UPDATE #{update_filter} ON #{table} WHEN NOT #{when_stmt} BEGIN
    DELETE FROM #{name} WHERE rowid = NEW.rowid;
  END;
  CREATE TRIGGER #{name}_delete AFTER DELETE ON #{table} BEGIN
    DELETE FROM #{name} WHERE rowid = OLD.rowid;
  END;
    SQL
  end

  def drop_secondary_trigger_sql(target_table, target_col, col)
    "DROP TRIGGER IF EXISTS #{target_table}_#{target_col}_#{col}_#{name}_update;"
  end

  def drop_secondary_trigger_poly_sql(target_table, target_col, col)
    "DROP TRIGGER IF EXISTS #{target_table}_#{target_col}_#{name}_update;"
  end

  def create_secondary_trigger_sql(target_table, target_col, col, primary_key)
    <<~SQL
      CREATE TRIGGER IF NOT EXISTS #{target_table}_#{target_col}_#{col}_#{name}_update AFTER UPDATE OF #{target_col} ON #{target_table} BEGIN
        #{rebuild_sql} AND #{table}.#{col} = NEW.#{primary_key};
      END;
    SQL
  end

  def create_secondary_trigger_poly_sql(target_table, target_col, col, conditions)
    conditions_sql = conditions.collect { |k, v| "NEW.#{k} = '#{v}'" }.join(" AND ")
    <<~SQL
      CREATE TRIGGER IF NOT EXISTS #{target_table}_#{target_col}_#{name}_insert AFTER INSERT ON #{target_table} WHEN #{conditions_sql} BEGIN
        #{rebuild_sql};
      END;
      CREATE TRIGGER IF NOT EXISTS #{target_table}_#{target_col}_#{name}_update AFTER UPDATE ON #{target_table} WHEN #{conditions_sql} BEGIN
        #{rebuild_sql};
      END;
    SQL
  end

  def drop_secondary_triggers_sql
    sql = +""
    @schema[:fields].each do |name, field|
      if field[:trigger_sql]
        if field[:col]
          sql << drop_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col])
        elsif field[:source]
          sql << drop_secondary_trigger_poly_sql(field[:target_table], field[:target_col], name)
        end
      end
    end
    sql.empty? ? nil : sql
  end

  def create_secondary_triggers_sql
    sql = +""
    @schema[:fields].each do |name, field|
      if field[:trigger_sql]
        if field[:col]
          sql << create_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col], field[:primary_key])
        elsif field[:source]
          sql << create_secondary_trigger_poly_sql(field[:target_table], field[:target_col], name, field[:conditions])
        end
      end
    end
    sql.empty? ? nil : sql
  end

  def rebuild_sql
    "INSERT OR REPLACE INTO #{name}(rowid, #{active_field_names.join(", ")}) SELECT #{table}.rowid, #{select_cols_sql} FROM #{joins_sql} #{filter_sql}"
  end

  def enrich_schema
    @schema[:fields].each do |name, field|
      if field[:target] && !field[:target].start_with?("#{table}.")
        field[:target] = field[:target].downcase
        target_table, target_col = field[:target].split(".")
        field[:primary_key] = :id unless field[:primary_key]
        field[:col] = :"#{name}_id" unless field[:col]
        field[:target_table] = target_table.to_sym
        field[:target_col] = target_col.to_sym
        field[:sql] = "(SELECT #{field[:target_col]} FROM #{field[:target_table]} WHERE #{field[:primary_key]} = NEW.#{field[:col]})"
        field[:trigger_sql] = true # create_secondary_trigger_sql(field[:target_table], field[:target_col], field[:col])
        field[:target_table_alias] = "#{field[:target_table]}_#{name}"
      elsif field[:source]
        field[:source] = field[:source].downcase
        target_table, target_col = field[:source].split(".")
        field[:target_table] = target_table.to_sym
        field[:target_col] = target_col.to_sym
        field[:conditions_sql] = field[:conditions].collect { |k, v| "#{k} = '#{v}'" }.join(" AND ") if field[:conditions]
        field[:sql] = "SELECT #{field[:target_col]} FROM #{field[:target_table]} WHERE #{field[:reference]} = NEW.id"
        field[:sql] += " AND #{field[:conditions_sql]}" if field[:conditions_sql]
        field[:sql] = "(#{field[:sql]})"
        field[:trigger_sql] = true
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
    sql = +""
    sql << " WHERE #{@schema[:filter_column]} = TRUE " if @schema[:filter_column]
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

  def joins_sql
    joins = [@schema[:table]]
    active_fields.each do |name, field|
      if field[:trigger_sql]
        join_table = +""
        join_table << "#{field[:target_table]} AS #{field[:target_table_alias]} ON "
        if field[:col]
          join_table << "#{field[:target_table_alias]}.#{field[:primary_key]} = #{@schema[:table]}.#{field[:col]}" if field[:col]
        elsif field[:source]
          join_table << "#{field[:target_table_alias]}.#{field[:reference]} = #{@schema[:table]}.rowid"
          if field[:conditions]
            join_table << " AND "
            join_table << field[:conditions].collect { |k, v| "#{field[:target_table_alias]}.#{k} = '#{v}'" }.join(" AND ")
          end
        end
        joins << join_table
      end
    end
    joins.join(" LEFT JOIN ")
  end
end
