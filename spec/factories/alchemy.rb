FactoryBot.define do
  factory :alchemy_configuration do
    api_key { "test-alchemy-key" }
  end

  factory :alchemy_wallet do
    sequence(:address) { |n| format("0x%040x", n) }
    name     { nil }
    networks { [ "eth-mainnet", "base-mainnet" ] }
    active   { true }
  end
end
