module LiteJob
  class Job
    module Countable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def all
          all_statement = DatabaseConnection.get_or_create_cached_statement :all, <<~SQL
            SELECT id, name, fire_at, value, created_at 
            FROM queue;
          SQL
          all_statement.execute!.map do |row|
            id, name, fire_at, value, created_at = row
            new(id: id, queue: name, fire_at: fire_at, serialized_value: value, created_at: created_at)
          end
        end

        def count(queue = nil)
          count_statement = DatabaseConnection.get_or_create_cached_statement :count, <<~SQL
            SELECT COUNT(*) FROM queue WHERE name = ? or ? IS NULL;
          SQL
          count_statement.execute!(queue)[0][0]
        end

        def unassigned_count
          unassigned_count_statement = DatabaseConnection.get_or_create_cached_statement :unassigned_count, <<~SQL
            SELECT COUNT(*) FROM queue 
            WHERE name != '_dead' AND name != 'processing';
          SQL
          unassigned_count_statement.execute![0][0]
        end

        def dead_count
          dead_count_statement ||= DatabaseConnection.get_or_create_cached_statement :dead_count, <<~SQL
            SELECT COUNT(*) FROM queue 
            WHERE name = '_dead';
          SQL
          dead_count_statement.execute![0][0]
        end
      end
    end
  end
end