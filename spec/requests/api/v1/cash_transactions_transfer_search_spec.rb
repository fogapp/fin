require "rails_helper"

# GET /api/v1/cash_transactions/transfer_search — drives the "find the
# other side of this transfer" picker on the txn detail page.
RSpec.describe "Api::V1::CashTransactions#transfer_search", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account_a)    { create(:account, name: "Checking") }
  let(:account_b)    { create(:account, name: "Savings") }

  let(:source) do
    create(:cash_transaction, :bank, account: account_a, amount: -500.00,
           transaction_date: Date.new(2026, 1, 15), description: "Wire out")
  end

  it "returns 401 without authentication" do
    get "/api/v1/cash_transactions/transfer_search",
        params: { transaction_id: source.id }
    expect(response).to have_http_status(:unauthorized)
  end

  describe "with no days param (default window)" do
    it "defaults to a ±14-day window" do
      in_window  = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                          transaction_date: Date.new(2026, 1, 10), description: "Wire in 5d earlier")
      out_window = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                          transaction_date: Date.new(2025, 12, 20), description: "Far older")

      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id },
          headers: auth_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |t| t["id"] }
      expect(ids).to     include(in_window.id)
      expect(ids).not_to include(out_window.id, source.id)
    end
  end

  describe "with an explicit days param" do
    it "honors a wider window" do
      pair = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                    transaction_date: Date.new(2026, 1, 5), description: "Wire in 10d ago")

      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id, days: 14 },
          headers: auth_headers
      expect(response.parsed_body.map { |t| t["id"] }).to include(pair.id)
    end

    it "clamps days to a maximum of 30" do
      pair = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                    transaction_date: Date.new(2026, 1, 15) - 25.days)

      # days=100 should clamp to 30, still capturing the 25-day-old pair
      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id, days: 100 },
          headers: auth_headers
      expect(response.parsed_body.map { |t| t["id"] }).to include(pair.id)

      # …but a 31-day-old pair is outside the clamped window
      far = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                   transaction_date: Date.new(2026, 1, 15) - 31.days)
      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id, days: 100 },
          headers: auth_headers
      expect(response.parsed_body.map { |t| t["id"] }).not_to include(far.id)
    end
  end

  it "excludes transactions that are already linked to a Transfer" do
    pair = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                  transaction_date: source.transaction_date)
    transfer = Transfer.create!(
      from_transaction_id: source.id, from_transaction_type: "CashTransaction",
      to_transaction_id:   pair.id,   to_transaction_type:   "CashTransaction",
      amount: 500.00
    )
    transfer.confirm!  # sets transfer_id on both sides

    get "/api/v1/cash_transactions/transfer_search",
        params: { transaction_id: source.id, days: 14 },
        headers: auth_headers
    expect(response.parsed_body.map { |t| t["id"] }).not_to include(pair.id)
  end

  it "returns serialized rows with account_name, amount, and description" do
    create(:cash_transaction, :bank, account: account_b, amount: 500.00,
           transaction_date: source.transaction_date, description: "Wire in")

    get "/api/v1/cash_transactions/transfer_search",
        params: { transaction_id: source.id, days: 14 },
        headers: auth_headers
    row = response.parsed_body.first
    expect(row.keys).to contain_exactly("id", "transaction_date", "description", "amount", "account_name",
                                        "amount_diff", "date_diff")
    expect(row["account_name"]).to eq("Savings")
    expect(row["amount"]).to       eq(500.0)
    expect(row["amount_diff"]).to  eq(0.0)
    expect(row["date_diff"]).to    eq(0)
  end

  describe "ranking" do
    it "puts the exact amount first, then the nearest date, and reports the gaps" do
      near_amount = create(:cash_transaction, :bank, account: account_b, amount: 480.00,
                           transaction_date: source.transaction_date, description: "Close but not it")
      exact_far   = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                           transaction_date: source.transaction_date + 6, description: "Exact, six days later")
      exact_near  = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                           transaction_date: source.transaction_date + 1, description: "Exact, next day")

      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id },
          headers: auth_headers

      rows = response.parsed_body
      expect(rows.map { |r| r["id"] }).to eq([ exact_near.id, exact_far.id, near_amount.id ])
      expect(rows.map { |r| r["date_diff"] }).to eq([ 1, 6, 0 ])
      expect(rows.last["amount_diff"]).to eq(20.0)
    end

    it "only offers money moving the opposite way, in a different account" do
      same_sign    = create(:cash_transaction, :bank, account: account_b, amount: -500.00,
                            transaction_date: source.transaction_date, description: "Another debit")
      same_account = create(:cash_transaction, :bank, account: account_a, amount: 500.00,
                            transaction_date: source.transaction_date, description: "Credit in same account")
      counterpart  = create(:cash_transaction, :bank, account: account_b, amount: 500.00,
                            transaction_date: source.transaction_date, description: "Wire in")

      get "/api/v1/cash_transactions/transfer_search",
          params: { transaction_id: source.id },
          headers: auth_headers

      ids = response.parsed_body.map { |r| r["id"] }
      expect(ids).to     include(counterpart.id)
      expect(ids).not_to include(same_sign.id, same_account.id)
    end
  end

  it "returns 400 with the missing-param name when transaction_id is omitted" do
    get "/api/v1/cash_transactions/transfer_search", headers: auth_headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to include("transaction_id")
  end
end
