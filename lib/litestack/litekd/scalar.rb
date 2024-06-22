module Litekd
  class Scalar
    
    include Litekd::TypeSerializer
    include Litekd::Callbacks
    
    attr_reader :typed, :key, :conn, :default
    
    def initialize(key, typed: :string, default: nil, expires_in: nil, after_change: nil)
      @key = key.to_s
      @conn = Litekd.connection
      @typed = typed || :string
      @default = default
      @after_change = after_change
      @expires_in = expires_in&.to_f
    end
    
    def value=(new_value)
      set(dump(new_value) )
    end
    
    def value = load(get || @default)    
    def remove = conn.delete_scalar_value(@key)
    def reset = self.value = @default
    def assgined? = exists?
    def to_s = get || default&.to_s
    def clear = remove
    def debug = conn.debug_scalar(@key)

    private 
    
    def get = conn.read_scalar_value(@key).flatten[0]
    def set(new_value) = change_and_callback(conn, :write_scalar_value, @key, new_value, @expires_in)
    def exists? = !get.nil?
  
  end
end
