FactoryBot.define do
  factory :investment_lot do
    security
    account
    acquired_date { Date.current }
    quantity      { 10 }
    cost_basis    { 1_000 }
  end
end
