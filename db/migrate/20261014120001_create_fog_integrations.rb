# frozen_string_literal: true

# fog-integration/1 with consent (fog:docs/integrations-contract.md): one
# row per app fog asked to connect to Fin. It starts pending, named by a
# one-time ticket whose page a household admin answers; approved, it holds
# the read-only API token minted for the app, with the plaintext encrypted
# until fog claims it exactly once; from then on it names the token so fog
# can report on and revoke it.
class CreateFogIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :fog_integrations, id: :uuid do |t|
      t.references :household, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :api_token, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      # The fog app connected, and which of Fin's offers.
      t.string :consumer, null: false
      t.string :offer, null: false
      t.string :state, null: false, default: "pending"
      # SHA-256 of the ticket in the consent page's address; the ticket
      # itself is told to fog once.
      t.string :ticket_digest, null: false
      # Where on fog the person goes after answering.
      t.string :return_to, null: false
      # The minted token's plaintext, encrypted, between approval and claim.
      t.text :secret
      t.datetime :expires_at, null: false
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :fog_integrations, :ticket_digest, unique: true
  end
end
