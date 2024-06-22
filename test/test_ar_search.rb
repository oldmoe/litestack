require "minitest/autorun"

# require_relative "../lib/litestack/litedb"
require "active_record"
require "active_record/base"

require_relative "patch_ar_adapter_path"

require_relative "../lib/active_record/connection_adapters/litedb_adapter"

ActiveRecord::Base.establish_connection(
  adapter: "litedb",
  database: ":memory:"
)

# ActiveRecord::Base.logger = Logger.new(STDOUT)

db = ActiveRecord::Base.connection.raw_connection
db.execute("CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE publishers(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE books(id INTEGER PRIMARY KEY, title TEXT, description TEXT, published_on TEXT, author_id INTEGER, publisher_id INTEGER, state TEXT, created_at TEXT, updated_at TEXT, active INTEGER)")
db.execute("CREATE TABLE reviews(id INTEGER PRIMARY KEY, book_id INTEGER)")
db.execute("CREATE TABLE comments(id INTEGER PRIMARY KEY, review_id INTEGER)")
# simulate action text
db.execute("CREATE TABLE rich_texts(id INTEGER PRIMARY KEY, body TEXT, record_id INTEGER, record_type TEXT, created_at TEXT, updated_at TEXT) ")
# custom primary and foreing key columns
db.execute("CREATE TABLE users(user_id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE posts(post_id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), author_id TEXT, title TEXT, content TEXT, created_at TEXT, updated_at TEXT)")

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
  has_many :reviews

  include Litesearch::Model

  litesearch do |schema|
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

class RichText < ApplicationRecord
  belongs_to :record, polymorphic: true

  def self.table_name
    "rich_texts"
  end
end

module ActionText
  class RichText < ::RichText
  end
end

class Review < ApplicationRecord
  belongs_to :book
  has_one :rich_text, as: :record

  include Litesearch::Model

  litesearch do |schema|
    schema.field :body, target: "rich_texts.body", as: :record
  end
end

class Comment < ApplicationRecord
  belongs_to :review
  has_one :rich_text, as: :record

  include Litesearch::Model

  litesearch do |schema|
    schema.field :body, rich_text: true
  end
end

# no table items was created
class Item < ApplicationRecord
  include Litesearch::Model

  litesearch do |schema|
    schema.field :name
  end
end

class User < ApplicationRecord
  self.primary_key = "user_id"

  has_many :posts, foreign_key: :author_id

  include Litesearch::Model
  litesearch do |schema|
      schema.fields %w[ name ]
      schema.primary_key :user_id
  end
end

class Post < ApplicationRecord
  self.primary_key = "post_id"

  belongs_to :author, class_name: "User", primary_key: :user_id

  include Litesearch::Model
  litesearch do |schema|
      schema.fields %w[ title content ]
      schema.field :author, target: "users.name", primary_key: :user_id
      schema.primary_key :post_id
  end
end

class TestActiveRecordLitesearch < Minitest::Test
  def setup
    Book.drop_index!
    Book.delete_all
    Author.delete_all
    Publisher.delete_all
    User.delete_all
    Post.delete_all
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
    u = User.create(name: "Gabriel")
    Post.create(author: u, title: "Post #1", content: "Whenever you create a table without specifying the WITHOUT ROWID option, you get an implicit auto-increment column called rowid. The rowid column store 64-bit signed integer that uniquely identifies a row in the table.")
    Post.create(author: u, title: "Post #2", content: "If a table has the primary key that consists of one column, and that column is defined as INTEGER then this primary key column becomes an alias for the rowid column.")
  end

  def test_polymorphic
    review = Review.create(book_id: 1)
    rt = RichText.create(record: review, body: "a new review")
    rs = Review.search("review")
    assert_equal 1, rs.length
    rt.destroy
    review.destroy
  end

  def test_rich_text
    review = Review.create(book_id: 1)
    rt = RichText.create(record: review, body: "a new review")
    comment = Comment.create(review: review)
    ct = RichText.create(record: comment, body: "a new comment on the review")
    rs = Comment.search("comment")
    assert_equal 1, rs.length
    ct.destroy
    comment.destroy
    rt.destroy
    review.destroy
  end

  def test_similar
    newbook = Book.create(title: "A night", description: "A tale of watching TV", published_on: "2006-08-08", state: "available", active: true, publisher_id: 2, author_id: 2)
    book = Book.find 1
    books = book.similar
    assert_equal 1, books.length
    assert_equal "A night", books.first.title
    newbook.destroy
  end

  def test_search
    rs = Author.search("Hanna")
    assert_equal 1, rs.length
    assert_equal Author, rs[0].class
  end

  def test_search_custom_primary_key
    rs = User.search("gabriel")
    assert_equal 1, rs.length
    assert_equal User, rs[0].class
  end

  def test_search_field
    rs = Book.search("author: Hanna")
    assert_equal 1, rs.length
    assert_equal Book, rs[0].class
  end

  def test_search_field_custom_primary_key
    rs = Post.search("author: gabriel")
    assert_equal 2, rs.length
    assert_equal true, [Post, Post] - [rs[0].class, rs[1].class] == []
  end

  def test_search_all
    rs = Book.search_all("Hanna", {models: [Author, Book]})
    assert_equal 2, rs.length
    assert_equal true, [Author, Book] - [rs[0].class, rs[1].class] == []
  end

  def test_search_all_custom_primary_key
    rs = Post.search_all("gabriel", {models: [Post, User]})
    assert_equal 3, rs.length
    assert_equal true, [Post, User, Post] - [rs[0].class, rs[1].class, rs[2].class] == []
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

  def test_uncreated_table
    db = ActiveRecord::Base.connection.raw_connection
    db.execute("CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
    rs = Item.search("some")
    assert_equal 0, rs.length
    Item.create(name: "some item")
    rs = Item.search("some")
    assert_equal 1, rs.length
    Item.create(name: "another item")
    rs = Item.search("item")
    assert_equal 2, rs.length
  end

  def test_ignore_tables
    assert_equal false, ActiveRecord::SchemaDumper.ignore_tables.empty?
    # we have created 8 models, one ignore regex for each
    assert_equal 8, ActiveRecord::SchemaDumper.ignore_tables.count
  end
end
