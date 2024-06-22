module Litesearch::Model
  def self.included(klass)
    klass.include InstanceMethods
    klass.extend ClassMethods
    klass.attribute :search_rank, :float if klass.respond_to? :attribute
    if !defined?(Sequel::Model).nil? && klass.ancestors.include?(Sequel::Model)
      klass.include Litesearch::Model::SequelInstanceMethods
      klass.extend Litesearch::Model::SequelClassMethods
      Sequel::Model.extend Litesearch::Model::BaseClassMethods
    elsif !defined?(ActiveRecord::Base).nil? && klass.ancestors.include?(ActiveRecord::Base)
      klass.include Litesearch::Model::ActiveRecordInstanceMethods
      klass.extend Litesearch::Model::ActiveRecordClassMethods
      ActiveRecord::Base.extend Litesearch::Model::BaseClassMethods
      Litesearch::Schema.prepend Litesearch::Model::ActiveRecordSchemaMethods
      # ignore FTS5 virtual and shadow tables when dumping the schema
      ActiveRecord::SchemaDumper.ignore_tables << /^#{klass.table_name}_search_idx.*$/
    end
  end

  module BaseClassMethods
    def search_models
      @@models ||= {}
    end
  end

  module InstanceMethods
    # rowid = id by default
    def rowid
      id
    end

    def similar(limit = 10)
      self.class.similar(rowid, limit)
    end
  end

  module ClassMethods

    def litesearch
      # it is possible that this code is running when there is no table created yet
      if !defined?(ActiveRecord::Base).nil? && ancestors.include?(ActiveRecord::Base)
        unless table_exists?
          # capture the schema block
          @schema = ::Litesearch::Schema.new
          @schema.model_class = self if @schema.respond_to? :model_class
          @schema.type :backed
          @schema.table table_name.to_sym
          yield @schema
          @schema.post_init
          @schema_not_created = true
          after_initialize do
            if self.class.instance_variable_get(:@schema_not_created)
              self.class.get_connection.search_index(self.class.index_name) do |schema|
                @schema.model_class = self.class if @schema.respond_to? :model_class
                schema.merge(self.class.instance_variable_get(:@schema))
              end
              self.class.instance_variable_set(:@schema_not_created, false)
            end
          end
          return nil
        end
      end
      idx = get_connection.search_index(index_name) do |schema|
        schema.type :backed
        schema.table table_name.to_sym
        schema.model_class = self if schema.respond_to? :model_class
        yield schema
        schema.post_init
        @schema = schema # save the schema
      end
      if !defined?(Sequel::Model).nil? && ancestors.include?(Sequel::Model)
        Sequel::Model.search_models[name] = self
      elsif !defined?(ActiveRecord::Base).nil? && ancestors.include?(ActiveRecord::Base)
        ActiveRecord::Base.search_models[name] = self
      end
      idx
    end

    def rebuild_index!
      get_connection.search_index(index_name).rebuild!
    end

    def drop_index!
      get_connection.search_index(index_name).drop!
    end

    def similar(rowid, limit = 10)
      conn = get_connection
      idx = conn.search_index(send(:index_name))
      r_a_h = conn.results_as_hash
      conn.results_as_hash = true
      rs = idx.similar(rowid, limit)
      conn.results_as_hash = r_a_h
      result = []
      rs.each do |row|
        obj = fetch_row(row["rowid"])
        obj.search_rank = row["search_rank"]
        result << obj
      end
      result
    end

    def search_all(term, options = {})
      options[:offset] ||= 0
      options[:limit] ||= 25
      options[:term] = term
      selects = []
      if (models = options[:models])
        models_hash = {}
        models.each do |model|
          models_hash[model.name] = model
        end
      else
        models_hash = search_models
      end
      # remove the models from the options hash before passing it to the query
      options.delete(:models)
      models_hash.each do |name, klass|
        selects << "SELECT '#{name}' AS model, rowid, -rank AS search_rank FROM #{index_name_for_table(klass.table_name)}(:term)"
      end
      conn = get_connection
      sql = selects.join(" UNION ") << " ORDER BY search_rank DESC LIMIT :limit OFFSET :offset"
      result = []
      rs = conn.query(sql, options) # , options[:limit], options[:offset])
      rs.each_hash do |row|
        obj = models_hash[row["model"]].fetch_row(row["rowid"])
        obj.search_rank = row["search_rank"]
        result << obj
      end
      rs.close
      result
    end

    def index_name
      "#{table_name}_search_idx"
    end

    def index_name_for_table(table)
      "#{table}_search_idx"
    end

    # create a new instance of self with the row as an argument
    def create_instance(row)
      new(row)
    end
  end

  module ActiveRecordSchemaMethods

    attr_accessor :model_class

    def field(name, attributes = {})
      keys = attributes.keys
      if keys.include?(:action_text) || keys.include?(:rich_text)
        attributes[:source] = begin
          "#{ActionText::RichText.table_name}.body"
        rescue
          "action_text_rich_texts.body"
        end
        attributes[:reference] = :record_id
        attributes[:conditions] = {record_type: model_class.name}
        attributes[:target] = nil
      elsif keys.include? :as
        attributes[:source] = attributes[:target] unless attributes[:source]
        attributes[:reference] = "#{attributes[:as]}_id"
        attributes[:conditions] = {"#{attributes[:as]}_type": model_class.name}
        attributes[:target] = nil
      end
      super(name, attributes)
    end

    def allowed_attributes
      super + [:polymorphic, :as, :action_text]
    end

  end

  module ActiveRecordInstanceMethods
    def rowid
      self.class.rowid(id)
    end
  end

  module ActiveRecordClassMethods
    def get_connection
      connection.raw_connection
    end

    def rowid(id)
      where(primary_key => id).limit(1).pluck(:rowid)&.first
    end

    def fetch_row(rowid)
      find_by("rowid = ?", rowid)
    end

    def search(term)
      if @schema_not_created
        get_connection.search_index(index_name) do |schema|
          schema.merge(@schema)
          schema.model_class = self if schema.respond_to? :model_class
        end
        @schema_not_created = false
      end
      self.select(
        "#{table_name}.*"
      ).joins(
        "INNER JOIN #{index_name} ON #{table_name}.rowid = #{index_name}.rowid AND rank != 0 AND #{index_name} MATCH ", Arel.sql("'#{term}'")
      ).select(
        "-#{index_name}.rank AS search_rank"
      ).order(
        Arel.sql("#{index_name}.rank")
      )
    end

    def create_instance(row)
      instantiate(row)
    end
  end

  module SequelInstanceMethods
    def rowid
      self.class.rowid(id)
    end

    def search_rank
      @values[:search_rank]
    end

    def search_rank=(rank)
      @values[:search_rank] = rank
    end
  end

  module SequelClassMethods
    def rowid(id)
      where(primary_key => id).get(:rowid)
    end

    def fetch_row(rowid)
      self[rowid]  # where(Sequel.lit("rowid = ?", rowid)).first
    end

    def get_connection
      db.instance_variable_get(:@raw_db)
    end

    def search(term)
      dataset.select(
        Sequel.lit("#{table_name}.*, -#{index_name}.rank AS search_rank")
      ).inner_join(
        Sequel.lit("#{index_name}(:term) ON #{table_name}.rowid = #{index_name}.rowid AND rank != 0", {term: term})
      ).order(
        Sequel.lit("rank")
      )
    end

    def create_instance(row)
      # we need to convert keys to symbols first!
      row.keys.each do |k|
        next if k.is_a? Symbol
        row[k.to_sym] = row[k]
        row.delete(k)
      end
      call(row)
    end
  end
end
