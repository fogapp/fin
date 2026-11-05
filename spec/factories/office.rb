FactoryBot.define do
  factory :office_configuration do
    base_url { "https://office.test" }
    api_key  { "office_testtoken" }
  end

  factory :office_sheet_export do
    dataset     { "transactions" }
    title       { "Transactions" }
    sequence(:document_id) { |n| 100 + n }
    sheet_name  { "Sheet1" }
    url         { "https://office.test/d/101" }
    filters     { {} }
    row_count   { 3 }
    column_count { 13 }
    last_exported_at { Time.current }
  end
end
