module Litekd
  class List < Composite
    
    def add(*members) = conn.transaction { members.flatten.each{ |member| push(member) } }
    def prepend(*members) = conn.transaction { members.flatten.each{ |member| lpush(member) } }
    def push(new_member) = change_and_callback(conn, :rpush_composite_member, @key, dump(new_member))
    def lpush(new_member) = change_and_callback(conn, :lpush_composite_member, @key, dump(new_member))
    def remove_member(member) = change_and_callback(conn, :delete_composite_member_by_value, @key, dump(member))
    def remove(member = nil) = member ? remove_member(member) : change_and_callback(conn, :delete_composite_structure, @key)
    def size = conn.count_composite_members(@key).flatten[0] 

    alias_method :append, :add
    alias_method :"<<", :push
    alias_method :unshift, :lpush
    alias_method :elements, :members
  end
end
