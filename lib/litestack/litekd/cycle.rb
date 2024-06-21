module Litekd
  class Cycle < Scalar
  
    def initialize(key, typed: :integer, default: 0, expires_in: nil, values: [])
      super(key, typed: typed, default: default, expires_in: expires_in)
      @values = values
    end
    
    alias_method :index, :value
    alias_method :"index=", :"value="

    def value = @values[index]
    def next = @values[self.index = ((self.index + 1) % @values.length)]
    def previous = @values[self.index = ((self.index - 1) % @values.length)]
    def reset = self.index = @default
    
  end
end
