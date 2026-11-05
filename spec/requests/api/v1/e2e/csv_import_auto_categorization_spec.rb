require "rails_helper"

# E2E flow: the user uploads a credit-card CSV that contains a transaction
# matching an existing MerchantRule. After the import completes, the
# transaction exists, is auto-categorized by the rules engine, and is
# visible through the merchant/category endpoints + /cashflow.
RSpec.describe "E2E: CSV import → auto-categorization", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:broker)       { create(:broker, name: "TestBank") }
  let(:account)      { create(:account, broker: broker) }
  let(:merchant)     { create(:merchant, name: "Starbucks") }
  let(:category)     { create(:category, name: "Coffee") }

  before do
    create(:merchant_rule, merchant: merchant, pattern: "STARBUCKS",
           category: category, priority: 0)
    Merchants::RuleMatcher.reset_cache
  end

  def cc_csv
    <<~CSV
      Transaction Date,Post Date,Description,Category,Type,Amount,Memo
      2026-01-15,2026-01-16,STARBUCKS RESERVE,Food,Sale,-7.25,
      2026-01-16,2026-01-17,WALMART GROCERY,Groceries,Sale,-42.00,
    CSV
  end

  it "imports a CSV, auto-tags rows via merchant rules, and surfaces them in downstream endpoints" do
    file = Rack::Test::UploadedFile.new(StringIO.new(cc_csv), "text/csv", true,
                                        original_filename: "amex.csv")

    expect {
      post "/api/v1/imports",
           params: { file: file, account_id: account.id, broker_id: broker.id },
           headers: auth_headers
    }.to change(CashTransaction, :count).by(2)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["status"]).to eq("completed")
    expect(response.parsed_body["imported_count"]).to eq(2)

    # Starbucks row should be tagged automatically; Walmart should be untagged.
    starbucks_txn = CashTransaction.find_by!(description: "STARBUCKS RESERVE")
    walmart_txn   = CashTransaction.find_by!(description: "WALMART GROCERY")

    expect(starbucks_txn.merchant_id).to eq(merchant.id)
    expect(starbucks_txn.category_id).to eq(category.id)
    expect(walmart_txn.merchant_id).to   be_nil

    # /merchants index reflects the new txn under Starbucks
    get "/api/v1/merchants", headers: auth_headers
    expect(response).to have_http_status(:ok)
    starbucks_row = response.parsed_body.find { |m| m["id"] == merchant.id }
    expect(starbucks_row["transaction_count"]).to eq(1)

    # /categories/:id rolls up the matched txn's spend
    get "/api/v1/categories/#{category.id}", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["total_count"]).to eq(1)
    expect(response.parsed_body["total_spend"]).to eq(7.25)

    # /cashflow renders successfully with the imported transactions
    get "/api/v1/cashflow", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).to include("summary", "monthly_spend", "top_categories")
    # top_categories is a ranked array of {id, name, amount, avg_monthly, largest}
    # rows — not the name => amount hash it used to be.
    coffee_row = response.parsed_body["top_categories"].find { |row| row["name"] == "Coffee" }
    expect(coffee_row).to be_present
    expect(coffee_row["amount"]).to eq(7.25)
  end

  it "marks the import as failed and records an error_log on unknown CSV formats" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("Unknown,Headers,Here\n1,2,3\n"),
      "text/csv", true, original_filename: "garbage.csv"
    )

    post "/api/v1/imports",
         params: { file: file, account_id: account.id, broker_id: broker.id },
         headers: auth_headers

    expect(response).to have_http_status(:unprocessable_content)
    body = response.parsed_body
    expect(body["status"]).to eq("failed")
    expect(body["error_log"]).to match(/Unrecognized file.*needs Date, Description, Amount/)
  end
end
