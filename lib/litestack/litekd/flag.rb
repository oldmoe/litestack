module Litekd
  class Flag < Scalar
  
    def initialize(key, typed: :integer, expires_in: nil)
      super(key, typed: typed, default: nil, expires_in: expires_in)
    end
    
    def mark(expires_in: nil, force: true)
      exists = marked?
      return false if exists && !force
      oei = @expires_in
      @expires_in = expires_in&.to_f
      self.value = 1
      @expires_in = oei  
      !exists          
    end
    
    def marked? = self.value == 1
   
  end
end
