class CreateWebauthnCredentialsAndInviteCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :webauthn_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      # external_id is the credential ID returned by the authenticator, used
      # to look up the credential during the assertion phase. base64 string.
      t.string  :external_id,   null: false
      t.text    :public_key,    null: false
      t.string  :nickname
      t.bigint  :sign_count,    null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true

    create_table :invite_codes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string     :code,        null: false
      t.references :household,   type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by,  type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :used_by,     type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string     :role,        null: false, default: "member"
      t.datetime   :expires_at
      t.datetime   :used_at

      t.timestamps
    end
    add_index :invite_codes, :code, unique: true
  end
end
