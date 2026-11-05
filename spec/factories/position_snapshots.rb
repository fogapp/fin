FactoryBot.define do
  factory :position_snapshot do
    account
    security
    as_of_date { Date.current }
    sequence(:source_row_hash) { |n| "pos-hash-#{n}" }
    quantity     { 10 }
    price        { 100.0 }
    market_value { 1000.0 }
    cost_basis   { 900.0 }
    asset_class  { "Equity" }
  end
end
