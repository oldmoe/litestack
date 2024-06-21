module Litekd
  module TypeConverter

    TYPE_DUMPER = {
      string: ->(v){ v.to_s },
      integer: ->(v){ v.to_i },
      float: ->(v){ v.to_f },
      boolean: ->(v){ v ? 1 : 0 },
      decimal: ->(v){ BigDecimal(v).to_s },
      json: ->(v){  Oj.dump(v, mode: :compat) },
      datetime: ->(v){ v.inspect }
    }

    TYPE_LOADER = {
      string: ->(v){ v.to_s },
      integer: ->(v){ v.to_i },
      float: ->(v){ v.to_f },
      boolean: ->(v){ 1 ? true : false },
      decimal: ->(v){ BigDecimal(v) },
      json: ->(v){  Oj.load(v, mode: :compat) },
      datetime: ->(v){ DateTime.parse(v) }
    }


    def dump(value)
      TYPE_DUMPER[@typed].call(value) 
    end
    
    def load(value)
      TYPE_LOADER[@typed].call(value) 
    end
  end
end
