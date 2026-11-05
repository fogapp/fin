class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :credit_card_transaction_tags do |t|
      t.references :credit_card_transaction, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :credit_card_transaction_tags,
              [ :credit_card_transaction_id, :tag_id ],
              unique: true, name: "index_cc_transaction_tags_unique"
  end
end
