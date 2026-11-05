# Manually tracked on-chain wallet addresses, synced via the Alchemy
# Portfolio API across one or more EVM networks. Each wallet links to an
# Account whose positions/balance are derived from on-chain token balances.
class CreateAlchemyWallets < ActiveRecord::Migration[8.1]
  def change
    create_table :alchemy_wallets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.uuid :account_id
      t.string :address, null: false
      t.string :name
      t.jsonb :networks, null: false, default: [ "eth-mainnet", "base-mainnet" ]
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
      t.index [ :household_id, :address ], unique: true
      t.index :account_id
    end
    add_foreign_key :alchemy_wallets, :households, on_delete: :cascade
    add_foreign_key :alchemy_wallets, :accounts, on_delete: :nullify
  end
end
