FactoryBot.define do
  factory :household do
    sequence(:name) { |n| "Household #{n}" }
  end
end
