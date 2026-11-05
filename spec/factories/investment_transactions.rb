FactoryBot.define do
  factory :investment_transaction do
    account
    transaction_type
    security
    trade_date { Date.current }
    sequence(:source_row_hash) { |n| "txn-hash-#{n}" }
    amount_usd  { 100.0 }
    quantity    { 10 }
    price_usd   { 10.0 }
  end
end
