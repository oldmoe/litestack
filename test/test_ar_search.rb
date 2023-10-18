require "minitest/autorun"
require_relative "../lib/litestack/litedb"
# require_relative '../lib/active_record/connection_adapters/litedb_adapter'
require "active_record"

ActiveRecord::Base.establish_connection(
  adapter: "litedb",
  database: ":memory:"
)

# ActiveRecord::Base.logger = Logger.new(STDOUT)

db = ActiveRecord::Base.connection.raw_connection
db.execute("CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE publishers(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE books(id INTEGER PRIMARY KEY, title TEXT, description TEXT, published_on TEXT, author_id INTEGER, publisher_id INTEGER, state TEXT, created_at TEXT, updated_at TEXT, active INTEGER)")

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

class Author < ApplicationRecord
  has_many :books
  has_many :publishers, through: :books

  include Litesearch::Model

  litesearch do |schema|
    schema.field :name
  end
end

class Publisher < ApplicationRecord
  has_many :books
  has_many :authors, through: :books

  include Litesearch::Model
end

class Book < ApplicationRecord
  belongs_to :author
  belongs_to :publisher

  include Litesearch::Model

  Book.litesearch do |schema|
    schema.fields [:description, :state]
    schema.field :publishing_year, col: :published_on
    schema.field :title, weight: 10
    schema.field :ignored, weight: 0
    schema.field :author, target: "authors.name"
    schema.field :publisher, target: "publishers.name", col: :publisher_id
    schema.filter_column :active
    schema.tokenizer :porter
  end
end

class TestActiveRecordLitesearch < Minitest::Test
  def setup
    Book.drop_index!
    Book.delete_all
    Author.delete_all
    Publisher.delete_all
    Book.litesearch do |schema|
      schema.fields [:description, :state]
      schema.field :publishing_year, col: :published_on
      schema.field :title, weight: 10
      schema.field :ignored, weight: 0
      schema.field :author, target: "authors.name"
      schema.field :publisher, target: "publishers.name", col: :publisher_id
      schema.filter_column :active
      schema.tokenizer :porter
    end
    Publisher.create(name: "Penguin")
    Publisher.create(name: "Adams")
    Publisher.create(name: "Flashy")
    Author.create(name: "Hanna Spiegel")
    Author.create(name: "David Antrop")
    Author.create(name: "Aly Lotfy")
    Author.create(name: "Osama Penguin")
    Book.create(title: "In a middle of a night", description: "A tale of sleep", published_on: "2008-10-01", state: "available", active: true, publisher_id: 1, author_id: 1)
    Book.create(title: "In a start of a night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: false, publisher_id: 2, author_id: 1)
  end

  def test_search
    rs = Author.search("Hanna")
    assert_equal 1, rs.length
    assert_equal Author, rs[0].class
  end

  def test_search_field
    rs = Book.search("author: Hanna")
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
    rs = Book.search("night tale")
    assert_equal 2, rs.length
    Book.rebuild_index!
    rs = Book.search("night tale")
    assert_equal 2, rs.length
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
    rs = Book.search("night tale")
    assert_equal 1, rs.length
    Book.rebuild_index!
    rs = Book.search("night tale")
    assert_equal 2, rs.length
  end

  def test_update_referenced_column
    rs = Book.search("Hanna")
    assert_equal 1, rs.length
    Author.find(1).update(name: "Hayat")
    rs = Book.search("Hanna")
    assert_equal 0, rs.length
    rs = Book.search("Hayat")
    assert_equal 1, rs.length
  end

  def test_rebuild_on_create
    Publisher.litesearch do |schema|
      schema.field :name
      schema.rebuild_on_create true
    end
    rs = Publisher.search("Penguin")
    assert_equal 1, rs.length
  end
end
