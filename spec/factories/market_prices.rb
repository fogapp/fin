FactoryBot.define do
  factory :market_price do
    security
    sequence(:date) { |n| Date.current - n.days }
    open  { 100.0 }
    high  { 105.0 }
    low   { 99.0 }
    close { 102.5 }
    adjusted_close { 102.5 }
    volume { 1_000_000 }
  end
end
