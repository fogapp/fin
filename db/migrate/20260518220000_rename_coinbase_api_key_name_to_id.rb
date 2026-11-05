class RenameCoinbaseApiKeyNameToId < ActiveRecord::Migration[8.1]
  def change
    rename_column :coinbase_configurations, :api_key_name, :api_key_id
  end
end
