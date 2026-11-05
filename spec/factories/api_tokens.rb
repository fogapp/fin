FactoryBot.define do
  factory :api_token do
    name { "Test Token" }
    expires_at { nil }
    user      { Current.user      || create(:user) }
    household { Current.household || create(:household) }

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end
