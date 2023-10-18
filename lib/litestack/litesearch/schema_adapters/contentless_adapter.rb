class Litesearch::Schema::ContentlessAdapter < Litesearch::Schema::BasicAdapter
  private

  def generate_sql
    super
    # @sql[:rebuild_index] = Litesearch::SchemaChangeException.new("You cannot rebuild a contentless index")
    # @sql[:rebuild] = Litesearch::SchemaChangeException.new("You cannot rebuild a contentless index")
  end

  def create_index_sql(active = false)
    col_names = active ? active_col_names_sql : col_names_sql
    "CREATE VIRTUAL TABLE #{name} USING FTS5(#{col_names}, content='', contentless_delete=1, tokenize='#{tokenizer_sql}')"
  end
end
