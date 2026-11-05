class AddTokenDigestToApiTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :api_tokens, :token_digest, :string

    # Backfill digest for any existing tokens (dev seed token, etc.)
    ApiToken.find_each do |t|
      t.update_columns(token_digest: Digest::SHA256.hexdigest(t.token))
    end

    add_index :api_tokens, :token_digest, unique: true
    change_column_null :api_tokens, :token_digest, false
  end

  def down
    remove_column :api_tokens, :token_digest
  end
end
