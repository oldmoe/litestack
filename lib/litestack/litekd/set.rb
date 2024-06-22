module Litekd
  class Set < Composite

    def add(*members) = conn.transaction { members.flatten.each{|member| push(member) } }
    def push(member) = change_and_callback(conn, :write_composite_member, @key, 0, dump(member))

    alias_method :append, :add
    alias_method :"<<", :push

  end
end
