module Litekd
  class UniqueList < List

    def push(member)
      conn.transaction do
        conn.delete_composite_member_by_value(@key, member)
        conn.rpush_composite_member(@key, member)
        _after_change
      end
    end
    
    def lpush(member)
      conn.transaction do
        conn.delete_composite_member_by_value(@key, member)
        conn.lpush_composite_member(@key, member)
        _after_change
      end
    end

  end
end
