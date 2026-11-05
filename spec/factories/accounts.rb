FactoryBot.define do
  factory :account do
    broker
    sequence(:name)           { |n| "Account #{n}" }
    sequence(:account_number) { |n| "...#{1000 + n}" }
    account_type { "Invt Mgmt" }
  end
end
