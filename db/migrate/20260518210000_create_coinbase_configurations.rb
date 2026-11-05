class CreateCoinbaseConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :coinbase_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :api_key_name
      t.text :api_key_secret
      t.timestamps
    end
  end
end
