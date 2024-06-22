require "minitest/autorun"
require_relative "../lib/litestack/litedb"

class TestStandaloneIndex < Minitest::Test
  def setup
    @db = Litedb.new(":memory:")
    @db.results_as_hash = true
    @idx = @db.search_index("idx") do |schema|
      schema.fields [:sender, :receiver, :body]
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify false
    end
    @id1 = @idx.add(sender: "Hamada", receiver: "Anwar", subject: "Computer is broken", body: "Really broken, it is in million pieces")
    @id2 = @idx.add(sender: "Foad", receiver: "Soad", subject: "A million dollars!", body: "In someone's account, he thought he was broke! saw it on the computer, what a piece!")
  end

  def test_similar
    id3 = @idx.add(sender: "Hamada", receiver: "Anwar", subject: "Re: Computer is broken", body: "broken, it is in a thousand pieces")
    id4 = @idx.add(sender: "Hamada", receiver: "Anwar", subject: "Re: Computer is broken", body: "broken, it is in a thousand and one pieces")
    rs = @idx.similar(@id1, 2)
    assert_equal 2, rs.length
    assert_equal id3, rs[0]["rowid"]
    assert_equal id4, rs[1]["rowid"]
  end

  def test_search
    rs = @idx.search("Hamada")
    assert_equal rs.length, 1
    assert_equal rs[0]["sender"], "Hamada"
    rs = @idx.search("million")
    assert_equal rs.length, 2
    rs = @idx.search("piece")
    assert_equal rs.length, 2
  end

  def test_search_ranking
    rs = @idx.search("million")
    assert_equal rs.length, 2
    assert_equal rs[0]["subject"], "A million dollars!"
  end

  def test_search_field
    rs = @idx.search("body: million")
    assert_equal rs.length, 1
    assert_equal rs[0]["subject"], "Computer is broken"
  end

  def test_update_schema_remove_field
    @idx.modify do |schema|
      schema.fields [:sender, :body]
      schema.field :subject, {weight: 10}
      schema.field :receiver, {weight: 0}
      schema.tokenizer :porter
    end
    rs = @idx.search("receiver: Soad")
    assert_equal rs.length, 0
  end

  def test_update_schema_remove_field_and_rebuild
    @idx.modify do |schema|
      schema.fields [:sender, :body]
      schema.field :subject, {weight: 10}
      schema.field :receiver, {weight: 0}
      schema.tokenizer :porter
    end
    @idx.rebuild!
    assert_raises { @idx.search("receiver: Soad") }
  end

  def test_update_schema_add_field
    assert_equal @idx.search("computer").length, 2
    @idx.modify do |schema|
      schema.fields [:sender, :body, :receiver, :urgency]
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify false
    end
    assert_equal @idx.search("computer").length, 2
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    assert_equal @idx.search("computer").length, 3
    assert_equal @idx.search("urgency: high").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (girl)").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (computer)").length, 0
  end

  def test_update_schema_add_field_and_rebuild
    assert_equal @idx.search("computer").length, 2
    @idx.modify do |schema|
      schema.fields [:sender, :body, :receiver, :urgency]
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search("computer").length, 2
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    assert_equal @idx.search("computer").length, 3
    assert_equal @idx.search("urgency: high").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (girl)").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (computer)").length, 0
  end

  def test_update_schema_add_field_remove_another_and_rebuild
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.search("computer").length, 3
    @idx.modify do |schema|
      schema.fields [:sender, :body, :urgency]
      schema.field :subject, {weight: 10}
      schema.field :receiver, {weight: 0}
      schema.tokenizer :porter
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search("Computer").length, 3
    assert_raises do
      @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    end
    assert_equal @idx.search("Computer").length, 3
    @idx.rebuild!
    @idx.add({sender: "Kamal", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    assert_equal @idx.search("computer").length, 4
    assert_equal @idx.search("urgency: high").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (girl)").length, 1
    assert_equal @idx.search("urgency: (high) AND subject: (computer)").length, 0
  end

  def test_update_schema_change_weights
    @idx.modify do |schema|
      schema.fields [:sender, :body, :receiver, :subject]
      schema.tokenizer :porter
    end
    rs = @idx.search("million")
    assert_equal rs[0]["sender"], "Hamada"
  end

  def test_count
    assert_equal @idx.count, 2
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.count, 3
  end

  def test_update_document
    @idx.add(rowid: @id1, sender: "Hamada", receiver: "Zaher", subject: "Computer is broken", body: "Really broken, it is in million pieces")
    assert_equal @idx.search("Anwar").length, 0
    assert_equal @idx.search("Zaher").length, 1
  end

  def test_remove_document
    @idx.remove(@id1)
    assert_equal @idx.count, 1
    assert_equal @idx.search("Anwar").length, 0
    assert_equal @idx.search("Soad").length, 1
  end

  def test_adding_fields_with_zero_weight
    @idx.modify do |schema|
      schema.fields [:sender, :body, :receiver]
      schema.field :subject, {weight: 10}
      schema.field :urgency, {weight: 0}
      schema.tokenizer :porter
    end
    assert_raises do
      @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?", urgency: "high"})
    end
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.search("computer").length, 3
  end

  def test_update_schema_change_tokenizer_auto_rebuild
    @idx.modify do |schema|
      schema.fields [:sender, :body, :receiver]
      schema.field :subject, {weight: 10}
      schema.tokenizer :trigram
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search("puter").length, 2
    @idx.add({sender: "Kamal", receiver: "Layla", subject: "How are the girls?", body: "I wanted to ask how are the girls doing with the computer?"})
    assert_equal @idx.search("puter").length, 3
  end
end
