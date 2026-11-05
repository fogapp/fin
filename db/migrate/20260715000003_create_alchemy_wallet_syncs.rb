# Per-(wallet, network) transaction-sync state: the incremental head cursor
# and resumable backfill progress. Rows are created lazily on first sync of
# a pair.
class CreateAlchemyWalletSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :alchemy_wallet_syncs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid     :household_id, null: false
      t.uuid     :alchemy_wallet_id, null: false
      t.string   :network, null: false
      t.bigint   :last_synced_block
      t.datetime :last_synced_at
      t.string   :backfill_status, null: false, default: "pending"
      t.bigint   :backfill_target_block
      t.jsonb    :backfill_cursor, null: false, default: {}
      t.integer  :backfill_transfer_count, null: false, default: 0
      t.text     :last_error
      t.timestamps

      t.index [ :alchemy_wallet_id, :network ], unique: true
      t.index :household_id
    end

    add_foreign_key :alchemy_wallet_syncs, :alchemy_wallets, on_delete: :cascade
    add_foreign_key :alchemy_wallet_syncs, :households, on_delete: :cascade
  end
end
