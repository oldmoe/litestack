module Litekd
  class Enum < Scalar
    def initialize(key, typed: :string, default: nil, expires_in: nil, values: [])
      super(key, typed: typed, default: default, expires_in: expires_in)
      @values = values
    end

    def method_missing(method, *params)
      method = method.to_s.strip
      if method.end_with? '?'
        v = method[0, method.length - 1]
        return self.value == v
      elsif method.end_with? '!'
        v = method[0, method.length - 1]
        self.value = v if @values.include? v
      else
        super
      end
    end

    def value=(new_value)
      super if @values.include? new_value
    end
    
    def reset = self.value = @default

  end
end
