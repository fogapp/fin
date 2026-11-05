FactoryBot.define do
  factory :plaid_item do
    sequence(:item_id)      { |n| "item-#{n}" }
    sequence(:access_token) { |n| "access-token-#{n}" }
    institution_id   { "ins_1" }
    institution_name { "Test Bank" }
    status           { "active" }
  end
end
