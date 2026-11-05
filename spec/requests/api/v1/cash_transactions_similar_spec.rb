require "rails_helper"

# GET /api/v1/cash_transactions/:id/similar — the detail pane's "have I paid
# this before?" list. Matching is pg_trgm on the raw descriptor, so store and
# order numbers inside an otherwise identical descriptor don't split a group.
RSpec.describe "Api::V1::CashTransactions#similar", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account, name: "Chase Sapphire") }

  def txn(description, amount: -12.00, date: Date.new(2026, 6, 1))
    create(:cash_transaction, account: account, description: description,
           amount: amount, transaction_date: date)
  end

  let(:source) { txn("SQ *BLUE BOTTLE 0042", amount: -6.50, date: Date.new(2026, 6, 20)) }

  it "returns 401 without authentication" do
    get "/api/v1/cash_transactions/#{source.id}/similar"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the same descriptor's history, newest first, and never the source row" do
    older = txn("SQ *BLUE BOTTLE 0042", amount: -6.50, date: Date.new(2026, 5, 20))
    newer = txn("SQ *BLUE BOTTLE 0042", amount: -7.00, date: Date.new(2026, 6, 10))

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["transactions"].map { |t| t["id"] }).to eq([ newer.id, older.id ])
    expect(body["transactions"].map { |t| t["match"] }).to all(eq("exact"))
    expect(body["total"]).to eq(2)
    expect(body["total_amount"]).to eq(-13.5)
  end

  it "matches a near-identical descriptor and marks it as similar" do
    near = txn("SQ *BLUE BOTTLE 0117")

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    row = response.parsed_body["transactions"].find { |t| t["id"] == near.id }
    expect(row).to include("description" => "SQ *BLUE BOTTLE 0117", "match" => "similar",
                           "account_name" => "Chase Sapphire")
  end

  it "treats a descriptor differing only in case as exact" do
    cased = txn("sq *blue bottle 0042")

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    row = response.parsed_body["transactions"].find { |t| t["id"] == cased.id }
    expect(row["match"]).to eq("exact")
  end

  it "leaves unrelated descriptions out" do
    unrelated = txn("SHELL OIL 4411")

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    expect(response.parsed_body["transactions"].map { |t| t["id"] }).not_to include(unrelated.id)
    expect(response.parsed_body["total"]).to eq(0)
  end

  it "caps the rows at 8 while reporting the full count and sum" do
    12.times { |i| txn("SQ *BLUE BOTTLE 0042", amount: -1.00, date: Date.new(2026, 5, 1) + i.days) }

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    expect(response.parsed_body["transactions"].size).to eq(8)
    expect(response.parsed_body["total"]).to eq(12)
    expect(response.parsed_body["total_amount"]).to eq(-12.0)
  end

  it "honors an explicit limit, clamped to 50" do
    12.times { txn("SQ *BLUE BOTTLE 0042") }

    get "/api/v1/cash_transactions/#{source.id}/similar", params: { limit: 3 }, headers: auth_headers
    expect(response.parsed_body["transactions"].size).to eq(3)

    get "/api/v1/cash_transactions/#{source.id}/similar", params: { limit: 500 }, headers: auth_headers
    expect(response.parsed_body["transactions"].size).to eq(12)
  end

  it "returns an empty result for a blank description" do
    blank = txn("   ")

    get "/api/v1/cash_transactions/#{blank.id}/similar", headers: auth_headers

    expect(response.parsed_body).to eq("transactions" => [], "total" => 0, "total_amount" => 0.0)
  end

  it "does not reach across households" do
    other_household = create(:household)
    # Built inside the other household so the account's broker is theirs too.
    theirs = Current.set(household: other_household) do
      create(:cash_transaction, account: create(:account),
                                description: "SQ *BLUE BOTTLE 0042", amount: -6.50,
                                transaction_date: Date.new(2026, 6, 1))
    end

    get "/api/v1/cash_transactions/#{source.id}/similar", headers: auth_headers

    expect(response.parsed_body["transactions"].map { |t| t["id"] }).not_to include(theirs.id)
  end
end
