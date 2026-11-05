# typed: true

# Per-household credentials for the Office instance (~/src/office): the
# base URL of the app and an API token minted there. Office authenticates
# its MCP endpoint with the same bearer token as its REST API, and a token
# acts as its owner, so this is one connection per household — whichever
# Office user minted the token owns every spreadsheet Fin creates.
#
# Both columns fall back to ENV (OFFICE_URL / OFFICE_API_TOKEN), so a
# deployment can configure the integration without a row.
class CreateOfficeConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :office_configurations, id: :uuid do |t|
      t.uuid :household_id, null: false
      t.string :base_url
      t.text :api_key
      # Office folder to file new spreadsheets in; nil is the library root.
      t.integer :default_folder_id
      t.timestamps
    end

    add_index :office_configurations, :household_id, unique: true
    add_foreign_key :office_configurations, :households, on_delete: :cascade
  end
end
