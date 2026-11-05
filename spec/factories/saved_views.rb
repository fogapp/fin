FactoryBot.define do
  factory :saved_view do
    sequence(:name) { |n| "Saved View #{n}" }
    filter_params { { from: "2025-01-01", group_by: "month" }.to_json }
  end
end
