class CreatePlaidConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :client_id
      t.text :secret
      t.string :environment, default: "production", null: false
      t.timestamps
    end
  end
end
