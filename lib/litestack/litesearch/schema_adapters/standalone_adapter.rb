class Litesearch::Schema::StandaloneAdapter < Litesearch::Schema::BasicAdapter
  def generate_sql
    super
    @sql[:move_content] = "ALTER TABLE #{name}_content RENAME TO #{name}_content_temp"
    @sql[:adjust_temp_content] = "UPDATE sqlite_schema SET sql (SELECT sql FROM sqlite_schema WHERE name = '#{name}_content') WHERE name = #{name}_content_temp"
    @sql[:restore_content] = "ALTER TABLE #{name}_content_temp RENAME TO #{name}_content"
    @sql[:rebuild] = "INSERT INTO #{name}(#{name}) VALUES ('rebuild')"
    @sql[:similar] = "SELECT rowid, *, -rank AS search_rank FROM #{name} WHERE #{name} = (#{@sql[:similarity_query]}) AND rowid != :rowid ORDER BY rank LIMIT :limit"
    @sql[:drop_content_table] = "DROP TABLE #{name}_content"
    @sql[:drop_content_col] = :drop_content_col_sql
    @sql[:create_content_table] = :create_content_table_sql
    @sql[:search] = "SELECT rowid, *, -rank AS search_rank FROM #{name}(:term) WHERE rank !=0 ORDER BY rank LIMIT :limit OFFSET :offset"
  end

  private

  def create_index_sql(active = false)
    col_names = active ? active_col_names_sql : col_names_sql
    "CREATE VIRTUAL TABLE #{name} USING FTS5(#{col_names}, tokenize='#{tokenizer_sql}')"
  end

  def drop_content_col_sql(col_index)
    "ALTER TABLE #{name}_content DROP COLUMN c#{col_index}"
  end

  def create_content_table_sql(count)
    cols = []
    count.times { |i| cols << "c#{i}" }
    "CREATE TABLE #{name}_content(rowid INTEGER PRIMARY KEY, #{cols.join(", ")})"
  end
end
