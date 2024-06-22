require_relative "schema_adapters"

class Litesearch::Schema
  TOKENIZERS = {
    porter: "porter unicode61 remove_diacritics 2",
    unicode: "unicode61 remove_diacritics 2",
    ascii: "ascii",
    trigram: "trigram"
  }

  INDEX_TYPES = {
    standalone: Litesearch::Schema::StandaloneAdapter,
    contentless: Litesearch::Schema::ContentlessAdapter,
    backed: Litesearch::Schema::BackedAdapter
  }

  DEFAULT_SCHEMA = {
    name: nil,
    type: :standalone,
    fields: nil,
    table: nil,
    filter_column: nil,
    tokenizer: :porter,
    auto_create: true,
    auto_modify: true,
    rebuild_on_create: false,
    rebuild_on_modify: false
  }

  attr_accessor :schema

  def initialize(schema = {})
    @schema = schema # DEFAULT_SCHEMA.merge(schema)
    @schema[:fields] = {} unless @schema[:fields]
  end

  def merge(other_schema)
    @schema.merge!(other_schema.schema)
  end

  # schema definition API
  def name(new_name)
    @schema[:name] = new_name
  end

  def type(new_type)
    raise "Unknown index type" if INDEX_TYPES[new_type].nil?
    @schema[:type] = new_type
  end

  def table(table_name)
    @schema[:table] = table_name
  end

  def primary_key(new_primary_key)
    @schema[:primary_key] = new_primary_key
  end

  def fields(field_names)
    field_names.each { |f| field f }
  end

  def field(name, attributes = {})
    name = name.to_s.downcase.to_sym
    attributes = {weight: 1}.merge(attributes).select { |k, v| allowed_attributes.include?(k) } # only allow attributes we know, to ease schema comparison later
    @schema[:fields][name] = attributes
  end

  def tokenizer(new_tokenizer)
    raise "Unknown tokenizer" if TOKENIZERS[new_tokenizer].nil?
    @schema[:tokenizer] = new_tokenizer
  end

  def filter_column(filter_column)
    @schema[:filter_column] = filter_column
  end

  def auto_create(boolean)
    @schema[:auto_create] = boolean
  end

  def auto_modify(boolean)
    @schema[:auto_modify] = boolean
  end

  def rebuild_on_create(boolean)
    @schema[:rebuild_on_create] = boolean
  end

  def rebuild_on_modify(boolean)
    @schema[:rebuild_on_modify] = boolean
  end

  def post_init
    @schema = DEFAULT_SCHEMA.merge(@schema)
  end

  # schema sql generation API

  def sql_for(method, *args)
    adapter.sql_for(method, *args)
  end

  # schema data structure API
  def get(key)
    @schema[key]
  end

  def get_field(name)
    @schema[:fields][name]
  end

  def adapter
    @adapter ||= INDEX_TYPES[@schema[:type]].new(@schema)
  end

  def reset_sql
    adapter.generate_sql
  end

  def order_fields(old_schema)
    adapter.order_fields(old_schema)
  end

  # should we do this at the schema objects level?
  def compare(other_schema)
    other_schema = other_schema.schema
    # are the schemas identical?
    # 1 - same fields?
    [:type, :tokenizer, :name, :table].each do |key|
      other_schema[key] = @schema[key] if other_schema[key].nil?
    end
    if @schema[:type] != other_schema[:type]
      raise Litesearch::SchemaChangeException.new "Cannot change the index type, please drop the index before creating it again with the new type"
    end
    changes = {tokenizer: @schema[:tokenizer] != other_schema[:tokenizer], table: @schema[:table] != other_schema[:table], removed_fields_count: 0, filter_column: @schema[:filter_column] != other_schema[:filter_column]}
    # check tokenizer changes
    if changes[:tokenizer] && !other_schema[:rebuild_on_modify]
      raise Litesearch::SchemaChangeException.new "Cannot change the tokenizer without an index rebuild!"
    end

    # check field changes
    keys = @schema[:fields].keys.sort
    other_keys = other_schema[:fields].keys.sort

    extra_keys = other_keys - keys
    extra_keys.each do |key|
      if other_schema[:fields][key][:weight] == 0
        other_schema[:fields].delete(key)
      end
    end

    other_keys = other_schema[:fields].keys.sort

    changes[:fields] = keys != other_keys # only acceptable change is adding extra fields
    changes[:extra_fields_count] = other_keys.count - keys.count
    # check for missing fields (please note that adding fields can work without a rebuild)
    if keys - other_keys != []
      raise Litesearch::SchemaChangeException.new "Missing fields from existing schema, they have to exist with weight zero until the next rebuild!"
    end

    # check field weights
    weights = keys.collect { |key| @schema[:fields][key][:weight] }
    other_weights = other_keys.collect { |key| other_schema[:fields][key][:weight] }
    changes[:weights] = weights != other_weights # will always be true if fields are added
    if (removed_count = other_weights.count { |w| w == 0 }) > 0
      changes[:removed_fields_count] = removed_count
    end
    # check field attributes, only backed tables have attributes
    attrs = keys.collect do |key|
      f = @schema[:fields][key].dup
      f.delete(:weight)
      f.select { |k, v| allowed_attributes.include? k }
    end
    other_attrs = other_keys.collect do |key|
      f = other_schema[:fields][key].dup
      f.delete(:weight)
      f.select { |k, v| allowed_attributes.include? k }
    end
    changes[:attributes] if other_attrs != attrs # this means that we will need to redefine the triggers if any are there and also the table definition if needed

    # return the changes
    changes
  end

  def clean
    removable = @schema[:fields].select { |name, f| f[:weight] == 0 }.collect { |name, f| name }
    removable.each { |name| @schema[:fields].delete(name) }
  end

  def allowed_attributes
    [:weight, :col, :target, :source, :conditions, :reference, :primary_key]
  end
end

class Litesearch::SchemaException < StandardError; end

class Litesearch::SchemaChangeException < StandardError; end
