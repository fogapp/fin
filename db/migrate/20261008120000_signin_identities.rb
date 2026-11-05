# frozen_string_literal: true

# Household sign-in (fog:docs/signin-proposal.md §15). An identity is a
# verified sign-in from an OpenID provider — fog, or any other — linked to a
# Fin user; never matched by email. A session from one carries the
# provider's sid, so a back-channel logout can end exactly it (sessions
# already expire: api_tokens.expires_at). A handoff is the one-time,
# one-minute code the callback gives the console to fetch its token with.
class SigninIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :issuer, null: false
      t.string :subject, null: false
      t.timestamps
    end
    add_index :identities, %i[issuer subject], unique: true
    add_index :identities, :subject

    add_column :api_tokens, :oidc_sid, :string
    add_column :api_tokens, :handoff_digest, :string
    add_column :api_tokens, :handoff_expires_at, :datetime
    add_index :api_tokens, :oidc_sid
    add_index :api_tokens, :handoff_digest, unique: true

    # Instance-wide state that belongs to no household. One row.
    # fog_attested_at: when Fin last proved it runs on fog
    # (FogClient::Signin::Proof) — from then on it signs people in through
    # fog only.
    create_table :instance_settings, id: :uuid do |t|
      t.boolean :singleton, null: false, default: true
      t.datetime :fog_attested_at
      t.timestamps
    end
    add_index :instance_settings, :singleton, unique: true
    add_check_constraint :instance_settings, "singleton", name: "instance_settings_one_row"
  end
end
