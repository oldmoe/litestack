require "oj"
require_relative "schema"

class Litesearch::Index
  DEFAULT_SEARCH_OPTIONS = {limit: 25, offset: 0}

  def initialize(db, name)
    @db = db # this index instance will always belong to this db instance
    @stmts = {}
    name = name.to_s.downcase.to_sym
    # if in the db then put in cache and return if no schema is given
    # if a schema is given then compare the new and the existing schema
    # if they are the same put in cache and return
    # if they differ only in weights then set the new weights, update the schema, put in cache and return
    # if they differ in fields (added/removed/renamed) then update the structure, then rebuild if auto-rebuild is on
    # if they differ in tokenizer then rebuild if auto-rebuild is on (error otherwise)
    # if they differ in both then update the structure and rebuild if auto-rebuild is on (error otherwise)
    load_index(name) if exists?(name)

    if block_given?
      schema = Litesearch::Schema.new
      schema.schema[:name] = name
      yield schema
      schema.post_init
      # now that we have a schema object we need to check if we need to create or modify and existing index
      if @db.transaction_active?
        if exists?(name)
          load_index(name)
          do_modify(schema)
        else
          do_create(schema)
        end
        prepare_statements
      else
        @db.transaction(:immediate) do
          if exists?(name)
            load_index(name)
            do_modify(schema)
          else
            do_create(schema)
          end
          prepare_statements
        end
      end
    elsif exists?(name)
      load_index(name)
      prepare_statements
    # an index already exists, load it from the database and return the index instance to the caller
    else
      raise "index does not exist and no schema was supplied"
    end
  end

  def load_index(name)
    # we cannot use get_config_value here since the schema object is not created yet, should we allow something here?
    @schema = begin
      Litesearch::Schema.new(Oj.load(@db.get_first_value("SELECT v from #{name}_config where k = ?", :litesearch_schema.to_s)))
    rescue
      nil
    end
    raise "index configuration not found, either corrupted or not a litesearch index!" if @schema.nil?
    self
  end

  def modify
    schema = Litesearch::Schema.new
    yield schema
    schema.schema[:name] = @schema.schema[:name]
    do_modify(schema)
  end

  def rebuild!
    if @db.transaction_active?
      do_rebuild
    else
      @db.transaction(:immediate) { do_rebuild }
    end
  end

  def add(document)
    @stmts[:insert].execute!(document)
    @db.last_insert_row_id
  end

  def remove(id)
    @stmts[:delete].execute!(id)
  end

  def count(term = nil)
    if term
      @stmts[:count].execute!(term)[0][0]
    else
      @stmts[:count_all].execute![0][0]
    end
  end

  # search options include
  # limit: how many records to return
  # offset: start from which record
  def search(term, options = {})
    options = DEFAULT_SEARCH_OPTIONS.merge(options)
    rs = @stmts[:search].execute(term, options[:limit], options[:offset])
    generate_results(rs)
  end

  def similar(rowid, limit = 10)
    #   pp term = @db.execute(@schema.sql_for(:similarity_query), id)
    rs = if @schema.schema[:tokenizer] == :trigram
      # just use the normal similarity approach for now
      # need to recondisder that for trigram indexes later
      @stmts[:similar].execute(rowid, limit) # standard:disable Style/IdenticalConditionalBranches
    else
      @stmts[:similar].execute(rowid, limit) # standard:disable Style/IdenticalConditionalBranches
    end

    generate_results(rs)
  end

  def clear!
    @stmts[:delete_all].execute!(rowid)
  end

  def drop!
    if @schema.get(:type) == :backed
      @db.execute_batch(@schema.sql_for(:drop_primary_triggers))
      if @schema.sql_for(:create_secondary_triggers)
        @db.execute_batch(@schema.sql_for(:drop_secondary_triggers))
      end
    end
    @db.execute(@schema.sql_for(:drop))
  end

  private

  def generate_results(rs)
    result = []
    if @db.results_as_hash
      rs.each_hash do |hash|
        result << hash
      end
    else
      result = rs.to_a
    end
    result
  end

  def exists?(name)
    @db.get_first_value("SELECT count(*) FROM SQLITE_MASTER WHERE name = ? AND type = 'table' AND (sql like '%fts5%' OR sql like '%FTS5%')", name.to_s) == 1
  end

  def prepare_statements
    stmt_names = [:insert, :delete, :delete_all, :drop, :count, :count_all, :search, :similar]
    stmt_names.each do |stmt_name|
      @stmts[stmt_name] = @db.prepare(@schema.sql_for(stmt_name))
    end
  end

  def do_create(schema)
    @schema = schema
    @schema.clean
    # create index
    @db.execute(schema.sql_for(:create_index, true))
    @db.execute_batch(schema.sql_for(:create_vocab_tables))
    # adjust ranking function
    @db.execute(schema.sql_for(:ranks, true))
    # create triggers (if any)
    if @schema.get(:type) == :backed
      @db.execute_batch(@schema.sql_for(:create_primary_triggers))
      if (secondary_triggers_sql = @schema.sql_for(:create_secondary_triggers))
        @db.execute_batch(secondary_triggers_sql)
      end
      @db.execute(@schema.sql_for(:rebuild)) if @schema.get(:rebuild_on_create)
    end
    set_config_value(:litesearch_schema, @schema.schema)
  end

  def do_modify(new_schema)
    changes = @schema.compare(new_schema)
    # ensure the new schema maintains field order
    new_schema.order_fields(@schema)
    # with the changes object decide what needs to be done to the schema
    requires_schema_change = false
    requires_trigger_change = false
    requires_rebuild = false
    if changes[:fields] || changes[:table] || changes[:tokenizer] || changes[:filter_column] || changes[:removed_fields_count] > 0 # any change here will require a schema change
      requires_schema_change = true
      # only a change in tokenizer
      requires_rebuild = changes[:tokenizer] || new_schema.get(:rebuild_on_modify)
      requires_trigger_change = (changes[:table] || changes[:fields] || changes[:filter_column]) && @schema.get(:type) == :backed
    end
    if requires_schema_change
      # 1. enable schema editing
      @db.execute("PRAGMA WRITABLE_SCHEMA = TRUE")
      # 2. update the index sql
      @db.execute(new_schema.sql_for(:update_index), new_schema.sql_for(:create_index))
      # 3. update the content table sql (if it exists)
      @db.execute(new_schema.sql_for(:update_content_table), new_schema.sql_for(:create_content_table, new_schema.schema[:fields].count))
      # adjust shadow tables
      @db.execute(new_schema.sql_for(:expand_data), changes[:extra_fields_count])
      @db.execute(new_schema.sql_for(:expand_docsize), changes[:extra_fields_count])
      @db.execute("PRAGMA WRITABLE_SCHEMA = RESET")
      # need to reprepare statements
    end
    if requires_trigger_change
      @db.execute_batch(new_schema.sql_for(:drop_primary_triggers))
      @db.execute_batch(new_schema.sql_for(:create_primary_triggers))
      if (secondary_triggers_sql = new_schema.sql_for(:create_secondary_triggers))
        @db.execute_batch(new_schema.sql_for(:drop_secondary_triggers))
        @db.execute_batch(secondary_triggers_sql)
      end
    end
    if changes[:fields] || changes[:table] || changes[:tokenizer] || changes[:weights] || changes[:filter_column]
      @schema = new_schema
      set_config_value(:litesearch_schema, @schema.schema)
      prepare_statements
      # save_schema
    end
    # update the weights if they changed
    @db.execute(@schema.sql_for(:ranks, true)) if changes[:weights]
    @db.execute_batch(@schema.sql_for(:create_vocab_tables))
    do_rebuild if requires_rebuild
  end

  def do_rebuild
    # remove any zero weight columns
    if @schema.get(:type) == :backed
      @db.execute_batch(@schema.sql_for(:drop_primary_triggers))
      if (secondary_triggers_sql = @schema.sql_for(:create_secondary_triggers))
        @db.execute_batch(@schema.sql_for(:drop_secondary_triggers))
      end
      @db.execute(@schema.sql_for(:drop))
      @db.execute(@schema.sql_for(:create_index, true))
      @db.execute_batch(@schema.sql_for(:create_primary_triggers))
      @db.execute_batch(secondary_triggers_sql) if secondary_triggers_sql
      @db.execute(@schema.sql_for(:rebuild))
    elsif @schema.get(:type) == :standalone
      removables = []
      @schema.get(:fields).each_with_index { |f, i| removables << [f[0], i] if f[1][:weight] == 0 }
      removables.each do |col|
        @db.execute(@schema.sql_for(:drop_content_col, col[1]))
        @schema.get(:fields).delete(col[0])
      end
      @db.execute("PRAGMA WRITABLE_SCHEMA = TRUE")
      @db.execute(@schema.sql_for(:update_index), @schema.sql_for(:create_index, true))
      @db.execute(@schema.sql_for(:update_content_table), @schema.sql_for(:create_content_table, @schema.schema[:fields].count))
      @db.execute("PRAGMA WRITABLE_SCHEMA = RESET")
      @db.execute(@schema.sql_for(:rebuild))
    end
    @db.execute_batch(@schema.sql_for(:create_vocab_tables))
    set_config_value(:litesearch_schema, @schema.schema)
    @db.execute(@schema.sql_for(:ranks, true))
  end

  def get_config_value(key)
    Oj.load(@db.get_first_value(@schema.sql_for(:get_config_value), key.to_s)) # rescue nil
  end

  def set_config_value(key, value)
    @db.execute(@schema.sql_for(:set_config_value), key.to_s, Oj.dump(value))
  end
end
