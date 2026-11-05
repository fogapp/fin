# frozen_string_literal: true

# A token's scope: `full` is what every token has been — it does whatever
# its user can do — and `read` answers GET, HEAD and the read-only MCP
# tools only, so a credential handed to another app (fog-integration/1)
# can show the household's money without being able to move it.
class AddScopeToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :scope, :string, null: false, default: "full"
  end
end
