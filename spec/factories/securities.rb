FactoryBot.define do
  factory :security do
    sequence(:ticker) { |n| "TICK#{n}" }
    sequence(:name)   { |n| "Security #{n}" }
    sequence(:cusip)  { |n| format("%09d", n) }
    security_type { "Common Stock" }

    # Watchlists moved from a securities.watched flag to per-household
    # SecurityWatch rows; the transient keeps `create(:security, watched: true)`
    # working across specs.
    transient do
      watched { false }
      watched_by { nil }
    end

    after(:create) do |security, evaluator|
      if evaluator.watched || evaluator.watched_by
        household = evaluator.watched_by || Current.household || Household.first || create(:household)
        SecurityWatch.unscoped.find_or_create_by!(household: household, security: security)
      end
    end

    trait :without_cusip do
      cusip { nil }
    end

    trait :without_ticker do
      ticker { nil }
    end
  end
end
