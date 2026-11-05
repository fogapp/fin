# typed: true

# Remembers rejected transfer-candidate pairs. Dismissing a candidate used
# to just destroy the unconfirmed Transfer row, so the next detection run
# re-created the same pair forever. A separate table (rather than a
# dismissed_at tombstone on transfers) keeps the transfers unique indexes
# free for genuine future pairings of the same transactions.
class CreateTransferDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_dismissals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :household_id,          null: false
      t.string :from_transaction_type, null: false
      t.uuid   :from_transaction_id,   null: false
      t.string :to_transaction_type,   null: false
      t.uuid   :to_transaction_id,     null: false
      t.timestamps

      t.index [ :from_transaction_id, :to_transaction_id ], unique: true,
              name: "index_transfer_dismissals_on_pair"
      t.index :household_id
    end
  end
end
