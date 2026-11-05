FactoryBot.define do
  factory :csv_import do
    sequence(:source_filename) { |n| "import-#{n}.csv" }
    status { :pending }
    kind   { :unknown }
  end
end
