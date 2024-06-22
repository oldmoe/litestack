module Litekd
  
  module Attributes

      def self.included(klass)
        [ :integer, :string, :float, :decimal, :datetime, :json, :boolean, :list, :unique_list, 
          :set, :ordered_set, :counter, :cycle, :enum, :slots, :slot, :limiter, :flag
        ].each do |method|
          klass.define_singleton_method(:"litekd_#{method}") do |name, key: nil, **args| 
            klass.define_method(name.to_sym) do 
              if ivar = instance_variable_get("@#{name}".to_sym) 
                return ivar
              else
                (attribute_key = key.respond_to?(:call) ? key.call(self) : self.send(key)) unless key.nil?
                attribute_key = "#{name}-#{klass.name}-#{self.id}" unless attribute_key
                instance_variable_set("@#{name}".to_sym, Litekd.send(method, attribute_key, **args))
              end
            end
          end
        end        
      end
  
  end
end
