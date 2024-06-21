module Litekd
  class Limiter < Counter

    def initialize(key, typed: :integer, default: 0, expires_in: nil, limit: 1)
      super(key, typed: typed, default: default, expires_in: expires_in)
      @limit = limit
    end
    
    def poke = increment(by: 1)
    def exceeded? = self.value > @limit
    
  end
end
