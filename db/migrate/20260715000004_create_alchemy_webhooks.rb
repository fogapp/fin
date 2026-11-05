# One Alchemy Address Activity webhook per (household, network), registered
# programmatically via the Notify API. The signing key authenticates inbound
# deliveries; external_id is Alchemy's webhook id ("wh_...").
class CreateAlchemyWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :alchemy_webhooks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid     :household_id, null: false
      t.string   :network, null: false
      t.string   :external_id, null: false
      t.text     :signing_key
      t.string   :url, null: false
      t.string   :status, null: false, default: "active"
      t.datetime :last_received_at
      t.text     :last_error
      t.timestamps

      t.index [ :household_id, :network ], unique: true
      t.index :external_id, unique: true
    end

    add_foreign_key :alchemy_webhooks, :households, on_delete: :cascade
  end
end
