class SetupTestTables < ActiveRecord::Migration::Current

  def change
    create_table :posts do |t|
      t.text :title, :content
      t.timestamps
    end

    create_table :comments do |t|
      t.string :content
      t.references :post
      t.timestamps
    end
  end

end
