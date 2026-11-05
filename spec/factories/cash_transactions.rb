FactoryBot.define do
  factory :cash_transaction do
    transaction_date { Date.current }
    amount { -42.50 }
    sequence(:source_row_hash) { |n| "ct-hash-#{n}" }
    description { "AMAZON.COM*ABC123" }
    transaction_type { "Sale" }
    source { "credit_card" }

    trait :credit_card do
      source { "credit_card" }
    end

    trait :bank do
      source { "bank" }
      amount { -50.00 }
      description { "ACH WITHDRAWAL" }
      transaction_type { "Debit" }
      balance { 1000.00 }
    end

    # Amount-based traits (used with :bank)
    trait :credit do
      amount { 200.00 }
      transaction_type { "Credit" }
    end

    trait :debit do
      amount { -75.00 }
      transaction_type { "Debit" }
    end

    trait :transfer do
      amount { -500.00 }
      transaction_type { "Account Transfer" }
    end

    # Credit-card type traits
    trait :sale do
      transaction_type { "Sale" }
      amount { -42.50 }
    end

    trait :payment do
      transaction_type { "Payment" }
      amount { 100.00 }
    end

    trait :return do
      transaction_type { "Return" }
      amount { 12.34 }
    end
  end
end
