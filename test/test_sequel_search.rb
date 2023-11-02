require_relative "../lib/litestack/litedb"
require_relative "../lib/sequel/adapters/litedb"
require "sequel"

DB = Sequel.connect(adapter: "litedb", database: ":memory:", max_connections: 1)

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

class Publisher < Sequel::Model
  one_to_many :books

  include Litesearch::Model
end

class Author < Sequel::Model
  one_to_many :books

  include Litesearch::Model

  litesearch do |schema|
    schema.field :name
  end
end

class Book < Sequel::Model
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
    schema.tokenizer :porter
  end
end

Publisher.create(name: "Penguin")
Publisher.create(name: "Adams")
Publisher.create(name: "Flashy")
Author.create(name: "Hanna Spiegel")
Author.create(name: "David Antrop")
Author.create(name: "Aly Lotfy")
Author.create(name: "Osama Penguin")
Book.create(title: "In a middle of a night", description: "A tale of sleep", published_on: "2008-10-01", state: "available", active: true, publisher_id: 1, author_id: 1)
Book.create(title: "In a start of a night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: false, publisher_id: 2, author_id: 2)

require "minitest/autorun"

class TestSequelLitesearch < Minitest::Test
  def setup
    #     Book.dataset.delete
    #     Author.dataset.delete
    #     Publisher.dataset.delete
    #     Book.litesearch do |schema|
    #       schema.fields [:description, :state]
    #       schema.field :publishing_year, col: :published_on
    #       schema.field :title, weight: 10
    #       schema.field :ignored, weight: 0
    #       schema.field :author, target: "authors.name", col: :publisher_id
    #       schema.field :publisher, target: "publishers.name", col: :publisher_id
    #       schema.filter_column :active
    #       schema.tokenizer :porter
    #     end
    #     #pp Book.get_connection.execute("select rowid from books_search_idx")
    #     #pp Book.get_connection.execute("select rowid from books_search_idx('Hanna')")
  end

  def test_similar
    newbook = Book.create(title: "A night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: true, publisher_id: 2, author_id: 2)     
    book = Book[1]
    books = book.similar
    assert_equal 1, books.length
    assert_equal "A night", books.first.title
    newbook.destroy
  end


  def test_search
    rs = Author.search("Hanna").all
    assert_equal 1, rs.length
    assert_equal Author, rs[0].class
  end

  def test_search_field
    rs = Book.search("description: sleep").all
    assert_equal 1, rs.length
    assert_equal Book, rs[0].class
  end

  def test_search_all
    rs = Book.search_all("Hanna")
    assert_equal 2, rs.length
    assert_equal true, [Author, Book] - [rs[0].class, rs[1].class] == []
  end

  def test_modify_schema
    Book.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.rebuild_on_modify true
    end
    rs = Book.search("night tale").all
    assert_equal 2, rs.length
    Book.rebuild_index!
    rs = Book.search("night tale").all
    assert_equal 2, rs.length
    Book.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.filter_column :active
      schema.rebuild_on_modify true
    end
  end

  def test_modify_schema_rebuild_later
    Book.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
    end
    rs = Book.search("night tale").all
    assert_equal 1, rs.length
    Book.rebuild_index!
    rs = Book.search("night tale").all
    assert_equal 2, rs.length
    Book.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.filter_column :active
      schema.rebuild_on_modify true
    end
  end

  def test_update_referenced_column
    rs = Book.search("Hanna").all
    assert_equal 1, rs.length
    Author[1].update(name: "Hayat")
    rs = Book.search("Hanna").all
    assert_equal 0, rs.length
    rs = Book.search("Hayat").all
    assert_equal 1, rs.length
    Author[1].update(name: "Hanna")
  end

  def test_rebuild_on_create
    Publisher.litesearch do |schema|
      schema.field :name
      schema.rebuild_on_create true
    end
    rs = Publisher.search("Penguin").all
    assert_equal 1, rs.length
  end
end
