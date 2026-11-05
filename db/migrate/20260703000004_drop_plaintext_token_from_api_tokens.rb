# The plaintext bearer token was persisted (and uniquely indexed) alongside
# its digest; authentication only ever reads the digest, so the plaintext
# column was pure liability — a DB dump revealed every live credential.
# The raw token is now only returned in-memory at creation time.
class DropPlaintextTokenFromApiTokens < ActiveRecord::Migration[8.1]
  def up
    remove_column :api_tokens, :token
  end

  def down
    add_column :api_tokens, :token, :string
    add_index :api_tokens, :token, unique: true
  end
end
