module Litekd
  class Counter < Scalar
  
    def initialize(key, typed: :integer, default: 0, expires_in: nil)
      super
      self.value = default  
    end
    
    def increment(by: 1) = conn.increment_scalar_value(by, @key)
    def decrement(by: 1) = conn.increment_scalar_value(by * -1, @key)
    
  end  
end
