module Litekd
  
  module ModelAttributes
    module ClassMethods
      
      def self.included(klass)
        [ :integer, :string, :float, :decimal, :datetime, :json, :boolean, :list, :unique_list, 
          :set, :ordered_set, :counter, :cycle, :enum, :slots, :slot, :limiter, :flag
        ].each { |method| self.define_class_method(:"litekd_#{method}") do |name, key: nil, **args| 
          attribute_key = key.respond_to?(:call) key.call : self.send(key) if key
          attribute_key = "#{self.class.name}-#{self.id}" unless attribute_key
          self.instance_variable_set("@#{attribute_key}".to_sym, Litekd.send(method, attribute_key, **args))
          self.define_method(attribute_key.to_sym) { self.instance_variable_get("@#{attribute_key}".to_sym) }
        end        
      end
       
    end
  
  end
end
