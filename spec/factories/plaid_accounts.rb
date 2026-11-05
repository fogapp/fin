FactoryBot.define do
  factory :plaid_account do
    plaid_item
    sequence(:plaid_account_id) { |n| "plaid-acct-#{n}" }
    sequence(:name)             { |n| "Plaid Account #{n}" }
    mask            { "1234" }
    account_type    { "depository" }
    account_subtype { "checking" }
  end
end
