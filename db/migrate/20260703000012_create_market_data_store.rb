# Phase 2 of docs/instruments_platform_design.md: the rebuilt price store.
# Candles carry provenance (source) and currency; quotes separate "current
# value" from EOD history; corporate actions make adjusted series honest;
# fx_rates end the everything-is-USD assumption; instrument_data_links pin
# exactly one provider per (instrument, capability).
class CreateMarketDataStore < ActiveRecord::Migration[8.1]
  def change
    create_table :candles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :security_id, null: false
      t.date :date, null: false
      t.string :granularity, null: false, default: "1d"
      t.decimal :open,  precision: 24, scale: 10
      t.decimal :high,  precision: 24, scale: 10
      t.decimal :low,   precision: 24, scale: 10
      t.decimal :close, precision: 24, scale: 10, null: false
      t.decimal :adjusted_close, precision: 24, scale: 10
      t.bigint :volume
      t.string :currency, null: false, default: "USD"
      t.string :source, null: false
      t.timestamps
      t.index %i[security_id granularity date], unique: true
      t.index %i[security_id date]
    end
    add_foreign_key :candles, :securities, on_delete: :cascade

    create_table :instrument_quotes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :security_id, null: false
      t.decimal :price, precision: 24, scale: 10, null: false
      t.decimal :change_pct_24h, precision: 10, scale: 4
      t.string :currency, null: false, default: "USD"
      t.string :source, null: false
      t.datetime :as_of, null: false
      t.timestamps
      t.index :security_id, unique: true
    end
    add_foreign_key :instrument_quotes, :securities, on_delete: :cascade

    create_table :corporate_actions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :security_id, null: false
      t.string :kind, null: false # split | dividend
      t.date :ex_date, null: false
      t.decimal :ratio, precision: 16, scale: 8   # splits: new/old
      t.decimal :amount, precision: 18, scale: 8  # dividends: per share
      t.string :currency, null: false, default: "USD"
      t.string :source, null: false
      t.timestamps
      t.index %i[security_id kind ex_date], unique: true
    end
    add_foreign_key :corporate_actions, :securities, on_delete: :cascade

    create_table :fx_rates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :base, null: false   # e.g. EUR
      t.string :quote, null: false  # e.g. USD
      t.date :date, null: false
      t.decimal :rate, precision: 24, scale: 10, null: false
      t.string :source, null: false
      t.timestamps
      t.index %i[base quote date], unique: true
    end

    create_table :instrument_data_links, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :security_id, null: false
      t.string :capability, null: false # candles | quotes | metadata | news
      t.string :provider, null: false   # alpha_vantage | coin_gecko | coin_market_cap | manual
      t.string :provider_ref
      t.integer :priority, null: false, default: 0
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :last_success_at
      t.datetime :last_attempt_at
      t.string :last_error
      t.boolean :disabled, null: false, default: false
      t.timestamps
      t.index %i[security_id capability], unique: true
      t.index :provider
    end
    add_foreign_key :instrument_data_links, :securities, on_delete: :cascade
  end
end
