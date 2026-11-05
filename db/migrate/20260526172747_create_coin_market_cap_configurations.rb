class CreateCoinMarketCapConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :coin_market_cap_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.text :api_key
      t.timestamps
    end
  end
end
