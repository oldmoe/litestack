require "minitest/autorun"
require_relative '../lib/litestack/litedb'

class TestLitesearch < Minitest::Test
  
  def setup
    @type = :backed
    @db = Litedb.new(":memory:")
    @db.results_as_hash = true
    @db.execute("CREATE TABLE person(id INTEGER PRIMARY KEY, name TEXT)")
    @db.execute("CREATE TABLE email(id INTEGER PRIMARY KEY, subject TEXT, sender_id INTEGER, receiver_id INTEGER, body TEXT, indexed INTEGER default 1)")
    @idx = @db.search_index('email_fts') do |schema|
      schema.type @type
      schema.table :email
      schema.fields [:body]
      schema.field :sender, {target: "person.name" }
      schema.field :receiver, {target: "person.name" }
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    @db.execute("INSERT INTO person(name) VALUES ('Hamada'), ('Sahar'), ('Hossam')")
    @db.execute("INSERT INTO email(subject, sender_id, receiver_id, body) VALUES ('hi', 1, 2, 'I just wanted to say hello'), ('re: hi', 2, 1, 'do I know you?')")
    @db.execute("INSERT INTO email(subject, sender_id, receiver_id, body) VALUES ('hi', 3, 2, 'hello')")
  end
  
  def test_search
    rs = @idx.search('Hamada')
    assert_equal 2, rs.length
    rs = @idx.search('hello')
    assert_equal 2, rs.length
    rs = @idx.search('hossam')
    assert_equal 1, rs.length
  end

  def test_search_ranking
    rs = @idx.search('hi')
    assert_equal 3, rs.length
    assert_equal 3, rs[0]['id'] 
  end
  
  def test_search_field
    rs = @idx.search('body: hello')
    assert_equal 2, rs.length
    assert_equal 3, rs[0]['id'] 
  end

  def test_search_with_array_output
    rah = @db.results_as_hash
    @db.results_as_hash = false
    rs = @idx.search('sender: hamada')
    assert_equal 1, rs[0][0]    
    @db.results_as_hash = rah
  end

  def test_load_index_from_cache
    idx = @db.search_index('email_fts')
    assert_equal true, idx != nil
    rs = @idx.search('body: know')
    assert_equal 1, rs.length
  end
  
  def test_load_index_from_db
    @db.instance_variable_get(:@litesearch_index_cache).delete(:email_fts) 
    idx = @db.search_index('email_fts')
    assert_equal true, idx != nil
    rs = @idx.search('body: know')
    assert_equal 1, rs.length
  end

  def test_load_index_from_db_with_a_schema
    @db.instance_variable_get(:@litesearch_index_cache).delete(:email_fts) 
    idx = @db.search_index('email_fts') do |schema|
      schema.type @type
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end    
    assert_equal true, idx != nil
    rs = @idx.search('body: know')
    assert_equal 1, rs.length
  end

  def test_update_schema_remove_field
    @db.execute("ALTER TABLE email ADD COLUMN urgency DEFAULT 'normal'")
    @idx.modify do |schema|
      schema.type @type
      schema.fields [:body, :urgency]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name", weight: 0}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    rs = @idx.search('receiver: Sahar')
    assert_equal 0, rs.length
    rs = @idx.search('sender: Hamada')
    assert_equal 1, rs.length
    rs = @idx.search('urgency: high')
    assert_equal 0, rs.length
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'high')")
    rs = @idx.search('urgency: high')
    assert_equal 1, rs.length
    @idx.rebuild!
    assert_raises do
      @idx.search('receiver: Soad')
    end
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'low')")
    rs = @idx.search('urgency: low')
    assert_equal 1, rs.length
  end
  
  def test_update_schema_remove_a_field
    @idx.modify do |schema|
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name", weight: 0}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    rs = @idx.search('receiver: Sarah')
    assert_equal rs.length, 0
  end

  def test_update_schema_remove_field_and_rebuild
    @idx.modify do |schema|
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name", weight: 0}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
    end
    @idx.rebuild!
    assert_raises{ @idx.search('receiver: Sarah') }
  end

  def test_update_schema_remove_field_and_auto_rebuild
    @idx.modify do |schema|
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name", weight: 0}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify true
    end
    assert_raises{ @idx.search('receiver: Sarah') }
  end



  def test_update_schema_add_field
    assert_equal @idx.search('computer').length, 0
    @db.execute("ALTER TABLE email ADD COLUMN urgency DEFAULT 'normal'")
    @idx.modify do |schema|
      schema.fields [:body, :urgency]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify false
    end
    assert_equal @idx.search('computer').length, 0
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'high')")
    assert_equal @idx.search('computer').length, 1
    assert_equal @idx.search('urgency: high').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (girl)').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (computer)').length, 0
  end

  def test_update_schema_add_field_and_rebuild
    assert_equal @idx.search('computer').length, 0
    @db.execute("ALTER TABLE email ADD COLUMN urgency DEFAULT 'normal'")
    @idx.modify do |schema|
      schema.fields [:body, :urgency]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search('computer').length, 0
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'high')")
    assert_equal @idx.search('computer').length, 1
    assert_equal @idx.search('urgency: high').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (girl)').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (computer)').length, 0
  end

  def test_update_schema_add_field_remove_another_and_rebuild
    assert_equal @idx.search('computer').length, 0
    @db.execute("ALTER TABLE email ADD COLUMN urgency DEFAULT 'normal'")
    @idx.modify do |schema|
      schema.fields [:body, :urgency]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name", weight: 0}
      schema.field :subject, {weight: 10}
      schema.tokenizer :porter
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search('computer').length, 0
    assert_raises do
      @idx.search('reciever: sarah')
    end
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'high')")
    assert_equal @idx.search('computer').length, 1
    assert_equal @idx.search('urgency: high').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (girl)').length, 1
    assert_equal @idx.search('urgency: (high) AND subject: (computer)').length, 0
  end
  
  def test_update_schema_change_weights
    @idx.modify do |schema|
      schema.fields [:body, :subject]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.tokenizer :porter
    end
    rs = @idx.search('hi')
    assert_equal rs[0]['id'], 3 
  end
  
  def test_count
    assert_equal @idx.count, 3
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer')")
    assert_equal @idx.count, 4
  end

  def test_remove_document
    @db.execute("DELETE FROM email where id > 1")
    assert_equal @idx.count, 1
    assert_equal @idx.search('Hossam').length, 0
    assert_equal @idx.search('Hamada').length, 1    
  end
  
  def test_update_document
    @db.execute("INSERT INTO email(id, sender_id, receiver_id, subject, body) VALUES (5, 1, 2, 'How are the cute girls?', 'I wanted to ask about the girls and the computer')")
    @db.execute("UPDATE email set subject = 'How are the lovely girls?' where id = 5")
    assert_equal @idx.search('cute').length, 0
    assert_equal @idx.search('lovely').length, 1
  end  
  
  def test_adding_fields_with_zero_weight
    @db.execute("ALTER TABLE email ADD COLUMN urgency DEFAULT 'normal'")
    @idx.modify do |schema|
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.field :subject, {weight: 10}
      schema.field :urgency, {weight: 0} 
      schema.tokenizer :porter
    end
    @db.execute("INSERT INTO email(sender_id, receiver_id, subject, body, urgency) VALUES (1, 2, 'How are the girls?', 'I wanted to ask about the girls and the computer', 'high')")
    assert_equal @idx.search('computer').length, 1
    assert_raises { @idx.search('urgency: high') }    
  end

=begin
  def test_update_schema_change_tokenizer_auto_rebuild
    @idx.modify do |schema|
      schema.fields [:body]
      schema.field :sender, {target: "person.name"}
      schema.field :receiver, {target: "person.name"}
      schema.field :subject, {weight: 10}
      schema.tokenizer :trigram
      schema.rebuild_on_modify true
    end
    assert_equal @idx.search('puter').length, 2
    @idx.add({sender: 'Kamal', receiver: 'Layla', subject: 'How are the girls?', body: 'I wanted to ask how are the girls doing with the computer?'})
    assert_equal @idx.search('puter').length, 3    
  end
=end
  
end 
