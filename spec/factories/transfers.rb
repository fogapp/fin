FactoryBot.define do
  factory :transfer do
    amount { 100.00 }

    trait :unconfirmed do
      confirmed_at { nil }
    end

    trait :confirmed do
      confirmed_at { Time.current }
    end
  end
end
