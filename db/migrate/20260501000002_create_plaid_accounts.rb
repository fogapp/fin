class CreatePlaidAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_accounts do |t|
      t.references :plaid_item,       null: false, foreign_key: true
      t.references :account,          null: true,  foreign_key: true
      t.string     :plaid_account_id, null: false
      t.string     :name,             null: false
      t.string     :mask
      t.string     :account_type
      t.string     :account_subtype

      t.timestamps
    end

    add_index :plaid_accounts, :plaid_account_id, unique: true
  end
end
