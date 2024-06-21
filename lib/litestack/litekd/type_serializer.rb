module Litekd
  module TypeSerializer

    def dump(value) = Serialize.send(@typed, value)    
    def load(value) = Deserialize.send(@typed, value)
    
    module Serialize
      def self.string(v) = v.to_s
      def self.integer(v) = v.to_i
      def self.float(v) = v.to_f
      def self.boolean(v) =  v ? 1 : 0 
      def self.decimal(v) = BigDecimal(v).to_s
      def self.json(v) = Oj.dump(v, mode: :compat)
      def self.datetime(v) = v.inspect 
    end
    
    module Deserialize
      def self.string(v) = v.to_s 
      def self.integer(v) = v.to_i
      def self.float(v) = v.to_f 
      def self.boolean(v) = 1 ? true : false
      def self.decimal(v) = BigDecimal(v) 
      def self.json(v) =  Oj.load(v, mode: :compat) 
      def self.datetime(v) = DateTime.parse(v) 
    end
    
  end
end
