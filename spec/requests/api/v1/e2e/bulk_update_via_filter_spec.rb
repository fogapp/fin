require "rails_helper"

# E2E flow: the user opens the filter sidebar, narrows down a set of
# transactions, then runs a bulk update (reassign account, add tags) on
# the result. Exercises cash_transactions#filter →
# CashTransactions::BulkUpdater → cash_transactions#bulk_update → list view.
RSpec.describe "E2E: bulk update via filter", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account_a)    { create(:account, name: "A") }
  let(:account_b)    { create(:account, name: "B") }
  let(:tag_food)     { create(:tag, name: "food") }
  let(:tag_business) { create(:tag, name: "business") }

  before do
    @star1 = create(:cash_transaction, :credit_card, account: account_a,
                    description: "STARBUCKS RESERVE", amount: -10.00,
                    transaction_date: Date.new(2026, 1, 10))
    @star2 = create(:cash_transaction, :credit_card, account: account_a,
                    description: "STARBUCKS COFFEE",  amount: -5.50,
                    transaction_date: Date.new(2026, 1, 12))
    @walmart = create(:cash_transaction, :credit_card, account: account_a,
                      description: "WALMART",           amount: -42.00,
                      transaction_date: Date.new(2026, 1, 13))
  end

  it "filters by description and bulk-updates the matched rows" do
    # 1 — Filter narrows to Starbucks transactions
    post "/api/v1/cash_transactions/filter",
         params: {
           conditions: [ { field: "description", operator: "contains", value: "STARBUCKS" } ],
           match_all: true
         },
         headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    starbucks_ids = response.parsed_body.map { |t| t["id"] }
    expect(starbucks_ids).to contain_exactly(@star1.id, @star2.id)

    # 2 — Bulk-update reassigns account + attaches tags
    post "/api/v1/cash_transactions/bulk_update",
         params: { ids: starbucks_ids, account_id: account_b.id,
                   tag_ids: [ tag_food.id, tag_business.id ] },
         headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["updated"]).to    eq(2)
    expect(body["account_id"]).to eq(account_b.id)
    expect(body["tag_ids"]).to    contain_exactly(tag_food.id, tag_business.id)

    # 3 — Persistence: the matched rows really did move to account B
    expect(@star1.reload.account_id).to eq(account_b.id)
    expect(@star2.reload.account_id).to eq(account_b.id)
    expect(@walmart.reload.account_id).to eq(account_a.id)

    expect(@star1.tags.map(&:id)).to contain_exactly(tag_food.id, tag_business.id)
    expect(@star2.tags.map(&:id)).to contain_exactly(tag_food.id, tag_business.id)
    expect(@walmart.tags).to be_empty

    # 4 — A subsequent index call reflects the new account
    get "/api/v1/cash_transactions", params: { account_id: account_b.id }, headers: auth_headers
    descriptions = response.parsed_body.map { |t| t["description"] }
    expect(descriptions).to     include("STARBUCKS COFFEE", "STARBUCKS RESERVE")
    expect(descriptions).not_to include("WALMART")
  end

  it "supports OR (match_all: false) for the filter step" do
    post "/api/v1/cash_transactions/filter",
         params: {
           conditions: [
             { field: "description", operator: "equals", value: "WALMART" },
             { field: "description", operator: "equals", value: "STARBUCKS COFFEE" }
           ],
           match_all: false
         },
         headers: auth_headers, as: :json
    expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(@walmart.id, @star2.id)
  end

  it "returns 400 when bulk_update is called with an empty ids list" do
    post "/api/v1/cash_transactions/bulk_update",
         params: { ids: [], account_id: account_b.id },
         headers: auth_headers, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "is idempotent when the same tag is bulk-applied twice" do
    post "/api/v1/cash_transactions/bulk_update",
         params: { ids: [ @star1.id ], tag_ids: [ tag_food.id ] },
         headers: auth_headers, as: :json

    expect {
      post "/api/v1/cash_transactions/bulk_update",
           params: { ids: [ @star1.id ], tag_ids: [ tag_food.id ] },
           headers: auth_headers, as: :json
    }.not_to change(CashTransactionTag, :count)

    expect(@star1.reload.tags.map(&:id)).to eq([ tag_food.id ])
  end
end
