FactoryBot.define do
  factory :estimated_tax_payment do
    tax_year { 2026 }
    jurisdiction { "federal" }
    paid_on { Date.new(2026, 4, 10) }
    amount { 5_000 }
  end

  factory :tax_checklist_item do
    tax_year { 2026 }
    kind { "other" }
    sequence(:source_label) { |n| "Source #{n}" }
    status { "expected" }
    auto_seeded { false }

    trait :seeded do
      auto_seeded { true }
    end
  end

  factory :tax_adjustment do
    tax_year { 2026 }
    kind { "income" }
    jurisdiction { "federal" }
    sequence(:label) { |n| "Adjustment #{n}" }
    amount { 100 }
  end
end
