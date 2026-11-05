FactoryBot.define do
  factory :recurring_series do
    sequence(:series_key) { |n| "desc:SERIES #{n}" }
    sequence(:name)       { |n| "Series #{n}" }
    status            { "suggested" }
    source            { "detected" }
    kind              { "subscription" }
    granularity       { "month" }
    quantity          { 1 }
    anchor            { { "day_of_month" => 15 } }
    average_amount    { 15.99 }
    last_amount       { 15.99 }
    min_amount        { 15.99 }
    max_amount        { 15.99 }
    amount_tolerance  { 0.075 }
    confidence        { 0.9 }
    first_charge_date { 6.months.ago.to_date }
    last_charge_date  { 1.month.ago.to_date }
    next_expected_date { Date.current + 3.days }

    trait :active do
      status      { "active" }
      accepted_at { 1.week.ago }
    end

    trait :weekly do
      granularity { "week" }
      anchor      { { "weekday" => 5 } }
    end

    trait :annual do
      granularity { "year" }
      anchor      { { "month" => 11, "day" => 3 } }
    end
  end

  factory :recurring_occurrence do
    recurring_series
    expected_date   { Date.current + 3.days }
    status          { "upcoming" }
    expected_amount { 15.99 }

    trait :paid do
      status       { "paid" }
      expected_date { 1.month.ago.to_date }
      charged_date { 1.month.ago.to_date }
      amount       { 15.99 }
    end
  end
end
