module Litekd
  class Slots < Counter

    def initialize(key, typed: :integer, default: 0, expires_in: nil, available: 1)
      super(key, typed: typed, default: default, expires_in: expires_in)
      @available = available
    end
    
    def reserve = (increment(by: 1) if self.value < @available)
    def release = (decrement(by: 1) if self.value > 0)
    def available? = self.value < @available
  end
end
