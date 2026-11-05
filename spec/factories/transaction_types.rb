FactoryBot.define do
  factory :transaction_type do
    sequence(:code) { |n| "TT#{format('%03d', n)}" }
    code_description { "Generic" }
    category { "Other" }

    trait :dividend do
      code { "011" }
      code_description { "DIV DOMEST" }
      category { "Dividend" }
    end

    trait :foreign_dividend do
      code { "012" }
      code_description { "DIV FOREIGN" }
      category { "Foreign Dividend" }
    end

    trait :interest do
      code { "020" }
      code_description { "INTEREST" }
      category { "Interest" }
    end

    trait :purchase do
      code { "100" }
      code_description { "BOUGHT" }
      category { "Purchase" }
    end

    trait :sale do
      code { "200" }
      code_description { "SOLD" }
      category { "Sale" }
    end
  end
end
