class CreateAccountBalanceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :account_balance_snapshots, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.decimal    :balance, null: false, precision: 15, scale: 2
      t.string     :source,  null: false  # scheduled | plaid_sync | manual
      t.datetime   :recorded_at, null: false
      t.timestamps
    end
    add_index :account_balance_snapshots, [ :account_id, :recorded_at ]
  end
end
