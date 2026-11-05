FactoryBot.define do
  factory :household_membership do
    user
    household
    role { "admin" }
  end
end
