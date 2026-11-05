FactoryBot.define do
  factory :broker do
    sequence(:name) { |n| "Broker #{n}" }
  end
end
