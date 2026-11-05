FactoryBot.define do
  factory :metric_point do
    metric_key { "monthly_spend" }
    date { Date.current.beginning_of_month }
    value { 100.0 }
    computed_at { Time.current }
  end
end
