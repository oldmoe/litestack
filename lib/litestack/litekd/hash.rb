module Litekd
  class Hash < Composite
    
    def add(hash) = conn.transaction { hash.each_pair{|hkey, value| push(hkey, value) } }
    def push(hkey, value) = change_and_callback(conn, :write_composite_member, @key, hkey.to_s, dump(value))
    def keys = conn.read_composite_positions(@key).flatten 
    def [](hkey) = conn.read_composite_member(@key, hkey.to_s).flatten[0] 
    def to_h = conn.read_composite_positions_and_members(@key).to_h 
    def remove_key(hkey) = change_and_callback(conn, :remove_composite_member_by_position, @key, hkey)
    def remove(hkey = nil) = hkey ? remove_key(hkey) : change_and_callback(conn, :delete_composite_structure, @key)    
  
    alias_method :update, :add
    alias_method :"<<", :push
    alias_method :"[]=", :push    
    alias_method :values, :members

  end
end
