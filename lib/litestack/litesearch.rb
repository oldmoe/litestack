module Litesearch
  class Index; end

  class Schema; end
end

require_relative "litesearch/index"
require_relative "litesearch/model"

module Litesearch
  def litesearch_index_cache
    @litesearch_index_cache ||= {}
  end

  def search_index(name)
    # normalize the index name
    # find the index in the db cache
    name = name.to_s.downcase.to_sym
    index = litesearch_index_cache[name]
    # if the index is in the cache and no block is given then return it
    return index if index && !block_given?
    # if either there is no index in the cache or a block is given
    # create a new index instance and then place it in the cache and return
    index = if block_given?
      Index.new(self, name) do |schema|
        yield schema
        schema.name(name)
      end
    else
      Index.new(self, name)
    end
    litesearch_index_cache[name] = index
  end
end
