class CreateSecurityOverviews < ActiveRecord::Migration[8.0]
  def change
    create_table :security_overviews, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :security, null: false, foreign_key: true, type: :uuid, index: { unique: true }

      t.string  :sector
      t.string  :industry
      t.string  :exchange
      t.string  :country
      t.string  :currency
      t.text    :description

      t.bigint  :market_cap
      t.bigint  :shares_outstanding
      t.bigint  :revenue_ttm

      t.decimal :pe_ratio,             precision: 18, scale: 6
      t.decimal :forward_pe,           precision: 18, scale: 6
      t.decimal :eps,                  precision: 18, scale: 6
      t.decimal :beta,                 precision: 18, scale: 6
      t.decimal :dividend_yield,       precision: 18, scale: 6
      t.decimal :dividend_per_share,   precision: 18, scale: 6
      t.decimal :week_52_high,         precision: 18, scale: 6
      t.decimal :week_52_low,          precision: 18, scale: 6
      t.decimal :analyst_target_price, precision: 18, scale: 6
      t.decimal :profit_margin,        precision: 18, scale: 6
      t.decimal :return_on_equity,     precision: 18, scale: 6

      t.date     :ex_dividend_date
      t.datetime :fetched_at

      t.timestamps
    end
  end
end
