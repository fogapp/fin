FactoryBot.define do
  factory :invite_code do
    household
    role { "member" }
    expires_at { 7.days.from_now }
  end
end
