require_relative "../lib/litestack/litedb"
require_relative "../lib/sequel/adapters/litedb"
require "sequel"

DB = Sequel.connect(adapter: "litedb", database: ":memory:", max_connections: 1)

TOKENIZER = :porter

DB.create_table(:publishers) do
  primary_key :id
  String :name
end

DB.create_table(:authors) do
  primary_key :id
  String :name
end

DB.create_table(:books) do
  primary_key :id
  String :title
  String :description
  String :published_on
  String :state
  Integer :active
  Integer :publisher_id
  Integer :author_id
end

class Publishers < Sequel::Model
  one_to_many :books

  include Litesearch::Model
end

class Authors < Sequel::Model
  one_to_many :books

  include Litesearch::Model

  litesearch do |schema|
    schema.field :name
  end
end

class Books < Sequel::Model
  many_to_one :author
  many_to_one :publisher

  include Litesearch::Model

  litesearch do |schema|
    schema.fields [:description, :state]
    schema.field :publishing_year, col: :published_on
    schema.field :title, weight: 10
    schema.field :ignored, weight: 0
    schema.field :author, target: "authors.name", col: :publisher_id
    schema.field :publisher, target: "publishers.name", col: :publisher_id
    schema.filter_column :active
    schema.tokenizer TOKENIZER
  end
end

Publishers.create(name: "Penguin")
Publishers.create(name: "Adams")
Publishers.create(name: "Flashy")
Authors.create(name: "Hanna Spiegel")
Authors.create(name: "David Antrop")
Authors.create(name: "Aly Lotfy")
Authors.create(name: "Osama Penguin")
Books.create(title: "In a middle of a night", description: "A tale of sleep", published_on: "2008-10-01", state: "available", active: true, publisher_id: 1, author_id: 1)
Books.create(title: "In a start of a night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: false, publisher_id: 2, author_id: 2)

require "minitest/autorun"

class TestSequelLitesearch < Minitest::Test
  def setup
    # nothing to do here
  end

  def test_similar
    newbook = Books.create(title: "A night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: true, publisher_id: 2, author_id: 2)
    book = Books[1]
    books = book.similar
    assert_equal 1, books.length
    assert_equal "A night", books.first.title
    newbook.destroy
  end

  def test_search
    rs = Authors.search("Hanna").all
    assert_equal 1, rs.length
    assert_equal Authors, rs[0].class
  end

  def test_search_field
    rs = Books.search("description: sleep").all
    assert_equal 1, rs.length
    assert_equal Books, rs[0].class
  end

  def test_search_all
    rs = Books.search_all("Hanna", models: [Authors, Books])
    assert_equal 2, rs.length
    assert_equal true, [Authors, Books] - [rs[0].class, rs[1].class] == []
  end

  def test_modify_schema
    Books.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.tokenizer TOKENIZER
      schema.rebuild_on_modify true
    end
    rs = Books.search("night tale").all
    assert_equal 2, rs.length
    Books.rebuild_index!
    rs = Books.search("night tale").all
    assert_equal 2, rs.length
    Books.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.filter_column :active
      schema.tokenizer TOKENIZER
      schema.rebuild_on_modify true
    end
  end

  def test_modify_schema_rebuild_later
    Books.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.tokenizer TOKENIZER
    end
    rs = Books.search("night tale").all
    assert_equal 1, rs.length
    Books.rebuild_index!
    rs = Books.search("night tale").all
    assert_equal 2, rs.length
    Books.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.tokenizer TOKENIZER
      schema.filter_column :active
      schema.rebuild_on_modify true
    end
  end

  def test_update_referenced_column
    rs = Books.search("Hanna").all
    assert_equal 1, rs.length
    Authors[1].update(name: "Hayat")
    rs = Books.search("Hanna").all
    assert_equal 0, rs.length
    rs = Books.search("Hayat").all
    assert_equal 1, rs.length
    Authors[1].update(name: "Hanna")
  end

  def test_rebuild_on_create
    Publishers.litesearch do |schema|
      schema.field :name
      schema.rebuild_on_create true
    end
    rs = Publishers.search("Penguin").all
    assert_equal 1, rs.length
  end
end
