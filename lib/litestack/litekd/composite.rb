module Litekd
  class Composite

    include Litekd::TypeSerializer

    attr_reader :typed, :key, :conn

    def initialize(key, typed: :string, default: nil, expires_in: nil)
      @key = key.to_s
      @conn = Litekd.connection
      @typed = typed || :string
      add(default) if default
    end
    
    def add(*members) = raise "not implemented"
    def count = conn.count_composite_members(@key).flatten[0]
    def members = conn.read_composite_members(@key).flatten.collect{|member| load(member)} 

    alias_method :size, :count
    
  end
end
