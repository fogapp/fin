require "rails_helper"

# E2E flow: the user has cash transactions that look like a transfer between
# two of their accounts, runs a scan, sees the candidate, confirms it, and
# the transfer_id propagates to both sides. Also confirms /cashflow still
# renders correctly with the transfer in place.
RSpec.describe "E2E: transfer detection → confirm", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account_a)    { create(:account, name: "Checking") }
  let(:account_b)    { create(:account, name: "Savings") }

  it "scans, surfaces a candidate, confirms it, and links both sides" do
    # Two real-looking cash transactions across two accounts on the same day
    from_txn = create(:cash_transaction, :bank, account: account_a,
                      amount: -500.00, transaction_date: Date.new(2026, 1, 15),
                      description: "Transfer to Savings")
    to_txn   = create(:cash_transaction, :bank, account: account_b,
                      amount:  500.00, transaction_date: Date.new(2026, 1, 15),
                      description: "Transfer from Checking")

    # 1 — User clicks "scan for transfers" in the UI
    perform_enqueued_jobs do
      post "/api/v1/transfers/scan", headers: auth_headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")
    end

    # 2 — A single Transfer candidate now exists, surfaced via /candidates
    get "/api/v1/transfers/candidates", headers: auth_headers
    expect(response).to have_http_status(:ok)
    candidates = response.parsed_body
    expect(candidates.length).to eq(1)
    cand = candidates.first
    expect(cand["amount"]).to eq(500.0)
    expect(cand["from_transaction_id"]).to eq(from_txn.id)
    expect(cand["to_transaction_id"]).to   eq(to_txn.id)
    expect(cand["from_account_id"]).to     eq(account_a.id)
    expect(cand["to_account_id"]).to       eq(account_b.id)

    candidate_id = cand["id"]

    # 3 — for_transaction lookup finds the same candidate from either side
    get "/api/v1/transfers/for_transaction",
        params: { transaction_id: from_txn.id, transaction_type: "CashTransaction" },
        headers: auth_headers
    expect(response.parsed_body["id"]).to eq(candidate_id)

    # 4 — User confirms the candidate
    post "/api/v1/transfers/#{candidate_id}/confirm", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["confirmed_at"]).not_to be_nil

    # 5 — transfer_id is now set on both underlying CashTransactions
    expect(from_txn.reload.transfer_id).to eq(candidate_id)
    expect(to_txn.reload.transfer_id).to   eq(candidate_id)

    # 6 — The transfer now shows up under confirmed transfers, not candidates
    get "/api/v1/transfers/candidates", headers: auth_headers
    expect(response.parsed_body).to be_empty

    get "/api/v1/transfers", params: { confirmed: "true" }, headers: auth_headers
    expect(response.parsed_body.map { |t| t["id"] }).to include(candidate_id)

    # 7 — /cashflow still renders and contains the expected keys
    get "/api/v1/cashflow", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).to include("monthly_income", "monthly_spend")
  end

  it "lets the user manually destroy a confirmed transfer, clearing both sides" do
    from_txn = create(:cash_transaction, :bank, account: account_a, amount: -100.00)
    to_txn   = create(:cash_transaction, :bank, account: account_b, amount:  100.00)

    post "/api/v1/transfers",
         params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                   to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                   amount: 100.00, auto_confirm: true },
         headers: auth_headers, as: :json
    expect(response).to have_http_status(:created)
    transfer_id = response.parsed_body["id"]

    expect(from_txn.reload.transfer_id).to eq(transfer_id)
    expect(to_txn.reload.transfer_id).to   eq(transfer_id)

    delete "/api/v1/transfers/#{transfer_id}", headers: auth_headers
    expect(response).to have_http_status(:no_content)
    expect(from_txn.reload.transfer_id).to be_nil
    expect(to_txn.reload.transfer_id).to   be_nil
    expect(Transfer.exists?(transfer_id)).to be false
  end
end
