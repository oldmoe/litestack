require "minitest/autorun"
require_relative "../lib/litestack/litedb"

class TestContentlessIndex < Minitest::Test
  def setup
    @db = Litedb.new(":memory:")
    @db.results_as_hash = true
    @idx = @db.search_index("idx") do |schema|
      schema.type :contentless
      schema.fields [:sender, :receiver, :body]
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    @idx.add(rowid: 1, sender: "Hamada", receiver: "Anwar", subject: "Computer is broken", body: "Really broken, it is in million pieces")
    @idx.add(rowid: 2, sender: "Foad", receiver: "Soad", subject: "A million dollars!", body: "In someone's bank account, he thought he was broke! saw it on the computer, what a piece!")
  end

  def test_similar
    @idx.add(rowid: 3, sender: "Hamada", receiver: "Anwar", subject: "Re: Computer is broken", body: "broken, it is in a thousand pieces")
    @idx.add(rowid: 4, sender: "Hamada", receiver: "Anwar", subject: "Re: Computer is broken", body: "broken, it is in a thousand and one pieces")
    rs = @idx.similar(1, 2)
    assert_equal 2, rs.length
    assert_equal 3, rs[0]["rowid"]
    assert_equal 4, rs[1]["rowid"]
  end

  def test_search
    rs = @idx.search("Hamada")
    assert_equal rs.length, 1
    assert_equal rs[0]["rowid"], 1
    rs = @idx.search("million")
    assert_equal rs.length, 2
    rs = @idx.search("piece")
    assert_equal rs.length, 2
  end

  def test_search_ranking
    rs = @idx.search("million")
    assert_equal rs.length, 2
    assert_equal rs[0]["rowid"], 2
  end

  def test_search_field
    rs = @idx.search("body: million")
    assert_equal rs.length, 1
    assert_equal rs[0]["rowid"], 1
  end

  def test_update_schema_remove_field
    @idx.modify do |schema|
      schema.type :contentless
      schema.fields [:sender, :body]
      schema.field :subject, {weight: 10}
      schema.field :receiver, {weight: 0}
      schema.tokenizer :porter
    end
    rs = @idx.search("receiver: Soad")
    assert_equal rs.length, 0
  end

  def test_update_schema_add_field
    @idx.modify do |schema|
      schema.type :contentless
      schema.fields [:sender, :body, :receiver, :urgency]
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    @idx.add({rowid: 3, sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    assert_equal @idx.search("computer").length, 3
    assert_equal @idx.search("urgency: high").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (girl)").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (computer)").length, 0
  end

  def test_update_schema_change_weights
    @idx.modify do |schema|
      schema.type :contentless
      schema.fields [:sender, :body, :receiver, :subject]
      schema.tokenizer :porter
    end
    rs = @idx.search("million")
    assert_equal rs[0]["rowid"], 1
  end

  def test_count
    assert_equal @idx.count, 2
    @idx.add({rowid: 3, sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.count, 3
  end

  def test_update_document
    @idx.add(rowid: 1, sender: "Hamada", receiver: "Zaher", subject: "Computer is broken", body: "Really broken, it is in million pieces")
    assert_equal @idx.search("Anwar").length, 0
    assert_equal @idx.search("Zaher").length, 1
  end

  def test_remove_document
    @idx.remove(1)
    assert_equal @idx.count, 1
    assert_equal @idx.search("Anwar").length, 0
    assert_equal @idx.search("Soad").length, 1
  end

  def test_adding_fields_with_zero_weight
    @idx.modify do |schema|
      schema.type :contentless
      schema.fields [:sender, :body, :receiver]
      schema.field :subject, {weight: 10}
      schema.field :urgency, {weight: 0}
      schema.tokenizer :porter
    end
    assert_raises do
      @idx.add({rowid: 3, sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    end
    @idx.add({rowid: 3, sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.search("computer").length, 3
  end
end
