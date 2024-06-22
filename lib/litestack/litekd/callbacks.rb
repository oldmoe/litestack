module Litekd
  module Callbacks
    
    def change_and_callback(object, method, *args)
      object.send(method, *args)
      _after_change
    end
  
    def _after_change 
      if @after_change
        @after_change.call(self) if @after_change.respond_to?(:call)
        self.send(@after_change.to_sym) if self.respond_to?(@after_change.to_sym)
      end 
    end  
      
  end
end
