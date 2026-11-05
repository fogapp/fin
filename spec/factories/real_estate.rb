FactoryBot.define do
  factory :real_estate_property do
    sequence(:name) { |n| "Property #{n}" }
    address_line1   { "5500 Grand Lake Dr" }
    city            { "San Antonio" }
    state           { "TX" }
    zip_code        { "78244" }
    status          { "owned" }
    sync_enabled    { true }
  end

  factory :real_estate_valuation do
    real_estate_property
    as_of  { Date.current }
    amount { 900_000 }
    source { "rentcast" }
  end

  factory :rentcast_configuration do
    api_key { "test-key" }
  end
end
