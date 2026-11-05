class CreateCategories < ActiveRecord::Migration[8.1]
  def up
    create_table :categories do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :categories, :name, unique: true

    # Seed from distinct raw_category values already present
    execute <<~SQL
      INSERT INTO categories (name, created_at, updated_at)
      SELECT DISTINCT raw_category, NOW(), NOW()
      FROM credit_card_transactions
      WHERE raw_category IS NOT NULL
      ORDER BY raw_category
    SQL

    add_reference :credit_card_transactions, :category, foreign_key: true, null: true
    add_reference :merchants, :category, foreign_key: true, null: true

    # Backfill category_id on existing transactions from their raw_category string
    execute <<~SQL
      UPDATE credit_card_transactions
      SET category_id = categories.id
      FROM categories
      WHERE credit_card_transactions.raw_category = categories.name
    SQL
  end

  def down
    remove_reference :merchants, :category, foreign_key: true
    remove_reference :credit_card_transactions, :category, foreign_key: true
    drop_table :categories
  end
end
