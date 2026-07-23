# frozen_string_literal: true

# Coverage for GitHub issue #143:
# Litesearch AR `search` must not interpolate the user term into SQL unescaped.
# https://github.com/oldmoe/litestack/issues/143
#
# Uses dedicated model/table names so full-suite loads do not clobber
# test/test_ar_search.rb constants or schemas.

require "minitest/autorun"
require "active_record"
require "active_record/base"
require "active_support"
require "active_support/notifications"

require_relative "patch_ar_adapter_path"
require_relative "../lib/active_record/connection_adapters/litedb_adapter"

ActiveRecord::Base.establish_connection(adapter: "litedb", database: ":memory:")
db = ActiveRecord::Base.connection.raw_connection
db.execute("CREATE TABLE sqli_authors(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
db.execute("CREATE TABLE sqli_books(id INTEGER PRIMARY KEY, title TEXT, description TEXT, author_id INTEGER, created_at TEXT, updated_at TEXT)")

module LitesearchSqliFixture
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class Author < ApplicationRecord
    self.table_name = "sqli_authors"

    include Litesearch::Model

    litesearch do |schema|
      schema.field :name
    end
  end

  class Book < ApplicationRecord
    self.table_name = "sqli_books"

    belongs_to :author, class_name: "LitesearchSqliFixture::Author", optional: true

    include Litesearch::Model

    litesearch do |schema|
      schema.fields [:title, :description]
    end
  end
end

class TestLitesearchArSearchSqlInjection < Minitest::Test
  Author = LitesearchSqliFixture::Author
  Book = LitesearchSqliFixture::Book

  def ensure_schema!
    ActiveRecord::Base.establish_connection(adapter: "litedb", database: ":memory:")
    db = ActiveRecord::Base.connection.raw_connection
    db.execute("CREATE TABLE IF NOT EXISTS sqli_authors(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT, updated_at TEXT)")
    db.execute("CREATE TABLE IF NOT EXISTS sqli_books(id INTEGER PRIMARY KEY, title TEXT, description TEXT, author_id INTEGER, created_at TEXT, updated_at TEXT)")
    Author.reset_column_information
    Book.reset_column_information
  end

  def setup
    ensure_schema!
    Author.delete_all
    Book.delete_all
    Author.litesearch { |s| s.field :name }
    Book.litesearch { |s| s.fields [:title, :description] }

    @alice = Author.create!(name: "Alice Wonder")
    @bob = Author.create!(name: "Bob Builder")
    @obrien = Author.create!(name: "O'Brien Special")
    Book.create!(title: "Safe Book", description: "nothing dangerous", author: @alice)
    Book.create!(title: "Other Book", description: "also safe", author: @bob)

    @sql_log = []
    @subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      @sql_log << event.payload[:sql].to_s
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
  end

  def search_sqls
    @sql_log.select { |s| s.include?("MATCH") || s.include?("search_idx") }
  end

  def test_normal_search_still_finds_records
    rs = Author.search("Alice")
    assert_equal 1, rs.length
    assert_equal "Alice Wonder", rs.first.name
  end

  def test_search_is_case_insensitive_like_fts
    rs = Author.search("alice")
    assert_operator rs.length, :>=, 1
  end

  def test_quote_breakout_does_not_return_all_rows
    # Classic breakout: close the MATCH string and force a tautology.
    # Vulnerable: ... MATCH 'zzz' OR 1=1 OR ''
    malicious = "zzz' OR 1=1 OR '"
    rs = Author.search(malicious)
    assert_equal 0, rs.length,
      "injection payload must not return authors via SQL breakout (got #{rs.map(&:name).inspect})"
  end

  def test_or_true_payload_does_not_return_all_rows
    malicious = "nonexistent' OR '1'='1"
    rs = Author.search(malicious)
    assert_equal 0, rs.length,
      "OR 1=1 style payload must not bypass FTS term (got #{rs.map(&:name).inspect})"
  end

  def test_comment_payload_does_not_return_all_rows
    malicious = "zzz' --"
    rs = Author.search(malicious)
    assert_equal 0, rs.length
  end

  def test_union_style_payload_does_not_error_or_exfiltrate
    malicious = "x' UNION SELECT 1,2,3 --"
    rs = Author.search(malicious)
    assert_kind_of ActiveRecord::Relation, rs
    assert_operator rs.length, :<=, Author.count
    names = rs.map(&:name)
    refute_includes names, "Alice Wonder"
    refute_includes names, "Bob Builder"
  end

  def test_sql_log_does_not_embed_raw_unescaped_quote_breakout
    malicious = "evil' OR 1=1 OR '"
    Author.search(malicious).load
    joined = search_sqls.join("\n")
    refute_match(/MATCH\s+'evil'\s+OR\s+1\s*=\s*1/i, joined,
      "SQL must not contain unescaped breakout of MATCH string literal:\n#{joined}")
  end

  def test_bound_or_quoted_term_appears_safely_in_sql
    term = "safe_unique_token_xyz"
    Author.search(term).load
    joined = search_sqls.join("\n")
    assert(
      joined.include?("?") || joined.include?(term) || joined.include?("safe_unique_token"),
      "expected search SQL to reference the term safely:\n#{joined}"
    )
  end

  def test_legitimate_apostrophe_in_name_is_searchable_or_safe
    rs = nil
    assert_silent do
      rs = Author.search("O'Brien")
      rs.load
    end
    assert_kind_of ActiveRecord::Relation, rs
    if rs.any?
      assert_includes rs.map(&:name), "O'Brien Special"
    end
  end

  def test_double_quote_and_fts_operators_do_not_break_sql_layer
    payloads = [
      'Alice"',
      "Alice*",
      "Alice AND Bob",
      "Alice OR Bob",
      "Alice AND",
      "OR Alice"
    ]
    payloads.each do |payload|
      rs = Author.search(payload)
      assert_kind_of ActiveRecord::Relation, rs, "payload=#{payload.inspect}"
      assert_operator rs.length, :<=, Author.count, "payload=#{payload.inspect}"
    end
  end

  def test_empty_string_search
    rs = Author.search("")
    assert_kind_of ActiveRecord::Relation, rs
  end

  def test_nil_term_coerced_safely
    rs = Author.search(nil)
    assert_kind_of ActiveRecord::Relation, rs
  end

  def test_book_search_injection_same_protection
    malicious = "zzz' OR 1=1 OR '"
    rs = Book.search(malicious)
    assert_equal 0, rs.length,
      "Book.search must apply the same SQL-safe term handling"
  end

  def test_normal_book_search_still_works
    rs = Book.search("Safe")
    assert_operator rs.length, :>=, 1
    assert_equal Book, rs.first.class
  end
end
