FactoryBot.define do
  factory :equity_company do
    sequence(:name) { |n| "Startup #{n}" }
    public_company { false }
    c_corp { true }
    qsbs_candidate { false }
  end

  factory :equity_fmv_entry do
    equity_company
    price_per_share { 10 }
    effective_date { Date.current }
    source { "409a" }
  end

  factory :equity_grant do
    equity_company
    grant_type { "iso" }
    grant_date { Date.current - 1.year }
    quantity { 4800 }
    strike_price { 1.25 }
    vesting_interval { "monthly" }
    vesting_occurrences { 48 }
    cliff_installments { 12 }

    trait :rsu do
      grant_type { "rsu" }
      strike_price { nil }
    end

    trait :fully_vested do
      vesting_interval { nil }
      vesting_occurrences { nil }
      cliff_installments { 0 }
    end
  end

  factory :equity_grant_event do
    equity_grant
    kind { "exercise" }
    occurred_on { Date.current }
    quantity { 1 }
  end
end
