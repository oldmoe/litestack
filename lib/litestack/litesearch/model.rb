module Litesearch::Model
                      
  def self.included(klass)
    klass.include InstanceMethods
    klass.extend ClassMethods 
    klass.attribute :search_rank, :float if klass.respond_to? :attribute
    if defined?(Sequel::Model) != nil && klass.ancestors.include?(Sequel::Model)
       klass.include Litesearch::Model::SequelInstanceMethods
       klass.extend Litesearch::Model::SequelClassMethods
       Sequel::Model.extend Litesearch::Model::BaseClassMethods
    elsif defined?(ActiveRecord::Base) != nil && klass.ancestors.include?(ActiveRecord::Base)
       klass.include Litesearch::Model::ActiveRecordInstanceMethods
       klass.extend Litesearch::Model::ActiveRecordClassMethods
       ActiveRecord::Base.extend Litesearch::Model::BaseClassMethods
    end
  end
  
  module BaseClassMethods
    def search_models
      @@models ||= {}
    end 
  end
  
  module InstanceMethods
  
  end
  
  module ClassMethods  
     
    def litesearch
      idx = get_connection.search_index(index_name) do |schema|
        schema.type :backed
        schema.table table_name.to_sym
        yield schema
        schema.post_init
        @schema = schema #save the schema   
      end
      if defined?(Sequel::Model) != nil && self.ancestors.include?(Sequel::Model)
        Sequel::Model.search_models[self.name] = self
      elsif defined?(ActiveRecord::Base) != nil && self.ancestors.include?(ActiveRecord::Base)
        ActiveRecord::Base.search_models[self.name] = self
      end
      idx
    end
    
    def rebuild_index!
      get_connection.search_index(index_name).rebuild!
    end
    
    def drop_index!
      get_connection.search_index(index_name).drop!
    end
    
    def search_all(term, options={})
      options[:offset] ||= 0
      options[:limit] ||= 25
      selects = [] 
      if models = options[:models]
        models_hash = {}
        models.each do |model|
          models_hash[model.name] = model
        end
      else
        models_hash = search_models
      end
      models_hash.each do |name, klass|
        selects << "SELECT '#{name}' AS model, rowid, -rank AS search_rank FROM #{index_name_for_table(klass.table_name)}('#{term}')"
      end
      conn = get_connection
      sql = selects.join(" UNION ") << " ORDER BY search_rank DESC LIMIT #{options[:limit]} OFFSET #{options[:offset]}"
      result = []
      rs = conn.query(sql) #, options[:limit], options[:offset])
      rs.each_hash do |row|
        obj = models_hash[row["model"]].fetch_row(row["rowid"])
        obj.search_rank = row["search_rank"]
        result << obj
      end
      rs.close
      result
    end
          
    # AR specific
                     
    private
    
    def index_name
      "#{table_name}_search_idx"
    end
    
    def index_name_for_table(table)
      "#{table}_search_idx"
    end
    
    # create a new instance of self with the row as an argument
    def create_instance(row)
      self.new(row)
    end
    
          
  end
  
  module ActiveRecordInstanceMethods;end
    
  module ActiveRecordClassMethods
    
    def get_connection
      connection.raw_connection
    end
    
    def fetch_row(id)
      find(id)
    end
    
    def search(term)
      self.select(
        "#{table_name}.*"
      ).joins(
        "INNER JOIN #{index_name} ON #{table_name}.id = #{index_name}.rowid AND rank != 0 AND #{index_name} MATCH ", Arel.sql("'#{term}'")
      ).select(
        "-#{index_name}.rank AS search_rank"
      ).order(
        Arel.sql("#{index_name}.rank")
      )        
    end

    private
    
    def create_instance(row)
      instantiate(row)
    end
  end
  
  module SequelInstanceMethods
  
    def search_rank
      @values[:search_rank]
    end
    
    def search_rank=(rank)
      @values[:search_rank] = rank
    end
        
  end
  
  module SequelClassMethods
        
    def fetch_row(id)
      self[id]
    end

    def get_connection
      db.instance_variable_get(:@raw_db)
    end

    def search(term)
      dataset.select(
        Sequel.lit("#{table_name}.*, -#{index_name}.rank AS search_rank")
      ).inner_join(
        Sequel.lit("#{index_name}('#{term}') ON #{table_name}.id = #{index_name}.rowid AND rank != 0")
      ).order(
        Sequel.lit('rank')
      )
    end

    private
    
    def create_instance(row)
      # we need to convert keys to symbols first!
      row.keys.each do |k|
        next if k.is_a? Symbol 
        row[k.to_sym] = row[k] 
        row.delete(k) 
      end
      self.call(row)
    end
  end
      
end
