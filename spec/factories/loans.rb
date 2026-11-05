FactoryBot.define do
  factory :loan do
    sequence(:name) { |n| "Loan #{n}" }
    loan_type          { "mortgage" }
    original_principal { 100_000 }
    interest_rate      { 6.0 }
    term_months        { 360 }
    start_date         { Date.current - 1.year }
    status             { "active" }
  end
end
