class AddSessionToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :session, :boolean, default: false, null: false
  end
end
