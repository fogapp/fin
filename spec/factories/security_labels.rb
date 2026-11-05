FactoryBot.define do
  factory :security_label do
    security
    household { Current.household || Household.first || create(:household) }
    sequence(:label) { |n| "Label #{n}" }
  end
end
