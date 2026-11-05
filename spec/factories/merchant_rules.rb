FactoryBot.define do
  factory :merchant_rule do
    merchant
    sequence(:pattern) { |n| "PATTERN#{n}" }
    priority { 0 }
  end
end
