require "rails_helper"

RSpec.describe "Api::V1::Transfers", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:from_txn)  { create(:cash_transaction, :bank, account: account_a, amount: -500.00) }
  let(:to_txn)    { create(:cash_transaction, :bank, account: account_b, amount:  500.00) }

  describe "GET /api/v1/transfers" do
    it "returns 401 without authentication" do
      get "/api/v1/transfers"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns transfers with denormalized transaction details" do
      Transfer.create!(
        from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
        to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
        amount: 500.00
      )

      get "/api/v1/transfers", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body.first
      expect(body).to include("from_transaction_id", "from_account_id", "to_account_id", "date_diff")
      expect(body["from_account_id"]).to eq(account_a.id)
      expect(body["to_account_id"]).to   eq(account_b.id)
    end

    it "filters by confirmed=true" do
      candidate = Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                                   to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                                   amount: 500.00)
      candidate.confirm!
      other_from = create(:cash_transaction, :bank, account: account_a, amount: -10)
      other_to   = create(:cash_transaction, :bank, account: account_b, amount: 10)
      Transfer.create!(from_transaction_id: other_from.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   other_to.id,   to_transaction_type:   "CashTransaction",
                       amount: 10)

      get "/api/v1/transfers", params: { confirmed: "true" }, headers: auth_headers
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first["id"]).to eq(candidate.id)
    end

    it "filters by confirmed=false (candidates only)" do
      Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                       amount: 500.00, confirmed_at: Time.current)
      candidate_from = create(:cash_transaction, :bank, account: account_a, amount: -10)
      candidate_to   = create(:cash_transaction, :bank, account: account_b, amount: 10)
      candidate = Transfer.create!(from_transaction_id: candidate_from.id, from_transaction_type: "CashTransaction",
                                   to_transaction_id:   candidate_to.id,   to_transaction_type:   "CashTransaction",
                                   amount: 10)

      get "/api/v1/transfers", params: { confirmed: "false" }, headers: auth_headers
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first["id"]).to eq(candidate.id)
    end
  end

  describe "GET /api/v1/transfers/candidates" do
    it "returns only unconfirmed transfers" do
      candidate = Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                                   to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                                   amount: 500.00)

      get "/api/v1/transfers/candidates", headers: auth_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |t| t["id"] }
      expect(ids).to eq([ candidate.id ])
    end
  end

  describe "GET /api/v1/transfers/for_transaction" do
    let!(:candidate) do
      Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                       amount: 500.00)
    end

    it "finds a candidate by the from side" do
      get "/api/v1/transfers/for_transaction",
          params: { transaction_id: from_txn.id, transaction_type: "CashTransaction" },
          headers: auth_headers
      expect(response.parsed_body["id"]).to eq(candidate.id)
    end

    it "finds a candidate by the to side" do
      get "/api/v1/transfers/for_transaction",
          params: { transaction_id: to_txn.id, transaction_type: "CashTransaction" },
          headers: auth_headers
      expect(response.parsed_body["id"]).to eq(candidate.id)
    end

    it "returns null when no candidate exists" do
      other = create(:cash_transaction, :bank, account: account_a, amount: -1)
      get "/api/v1/transfers/for_transaction",
          params: { transaction_id: other.id, transaction_type: "CashTransaction" },
          headers: auth_headers
      expect(response.parsed_body).to be_nil
    end
  end

  describe "POST /api/v1/transfers/scan" do
    it "queues the detect-candidates job and returns queued" do
      expect {
        post "/api/v1/transfers/scan", headers: auth_headers
      }.to have_enqueued_job(DetectTransferCandidatesJob)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")
    end
  end

  describe "POST /api/v1/transfers" do
    it "creates a transfer and syncs transfer_id without confirming" do
      expect {
        post "/api/v1/transfers",
             params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                       amount: 500.00 },
             headers: auth_headers, as: :json
      }.to change(Transfer, :count).by(1)

      expect(response).to have_http_status(:created)
      transfer = Transfer.last
      expect(transfer.confirmed_at).to be_nil
      expect(from_txn.reload.transfer_id).to eq(transfer.id)
    end

    it "auto-confirms when auto_confirm is set" do
      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                     amount: 500.00, auto_confirm: true },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Transfer.last.confirmed_at).not_to be_nil
    end

    it "creates a one-sided transfer with a counterparty account" do
      external = create(:account, kind: "external", broker: nil, account_number: nil, name: "Schwab")

      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     counterparty_account_id: external.id, amount: 500.00, auto_confirm: true },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["counterparty_account_id"]).to eq(external.id)
      expect(body["counterparty_account_name"]).to eq("Schwab")
      expect(body["to_transaction_id"]).to be_nil

      expect(from_txn.reload.transfer_id).to eq(body["id"])
    end

    it "classifies kind and include_in_spend from the legs, like auto-detection" do
      card = create(:account, account_type: "Credit Card", name: "Card")
      to_card = create(:cash_transaction, :bank, account: card, amount: 500.00)

      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     to_transaction_id:   to_card.id,  to_transaction_type:   "CashTransaction",
                     amount: 500.00 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["kind"]).to eq("credit_card_payment")
      expect(body["include_in_spend"]).to eq(false)
    end

    it "defaults include_in_spend to true for a one-sided payment to an external card" do
      external_card = create(:account, kind: "external", account_type: "Credit Card", broker: nil, account_number: nil, name: "Visa")

      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     counterparty_account_id: external_card.id, amount: 500.00 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["kind"]).to eq("credit_card_payment")
      expect(body["include_in_spend"]).to eq(true)
    end

    it "lets an explicit kind override the classifier's guess" do
      untyped_external = create(:account, kind: "external", account_type: nil, broker: nil, account_number: nil, name: "My Card (untracked)")

      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     counterparty_account_id: untyped_external.id, amount: 500.00,
                     kind: "credit_card_payment", include_in_spend: true },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["kind"]).to eq("credit_card_payment")
      expect(body["include_in_spend"]).to eq(true)
    end

    it "rejects a one-sided transfer without a counterparty account" do
      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     amount: 500.00 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a counterparty when both sides are given" do
      external = create(:account, kind: "external", broker: nil, account_number: nil)

      post "/api/v1/transfers",
           params: { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                     counterparty_account_id: external.id, amount: 500.00 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/transfers with one-sided rows" do
    it "serializes the absent side as null and names the counterparty" do
      external = create(:account, kind: "external", broker: nil, account_number: nil, name: "Schwab")
      t = Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                           counterparty_account_id: external.id, amount: 500.00)
      t.confirm!

      get "/api/v1/transfers", headers: auth_headers
      expect(response).to have_http_status(:ok)
      row = response.parsed_body.find { |r| r["id"] == t.id }
      expect(row["counterparty_account_id"]).to eq(external.id)
      expect(row["counterparty_account_name"]).to eq("Schwab")
      expect(row["from_account_id"]).to eq(account_a.id)
      expect(row["to_transaction_id"]).to be_nil
      expect(row["to_account_id"]).to be_nil
      expect(row["to_date"]).to be_nil
      expect(row["date_diff"]).to be_nil
    end
  end

  describe "POST /api/v1/transfers/:id/confirm" do
    it "confirms a candidate" do
      candidate = Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                                   to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                                   amount: 500.00)

      post "/api/v1/transfers/#{candidate.id}/confirm", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(candidate.reload.confirmed_at).not_to be_nil
    end
  end

  describe "PATCH /api/v1/transfers/:id" do
    let(:transfer) do
      Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                       amount: 500.00)
    end

    it "returns 401 without authentication" do
      patch "/api/v1/transfers/#{transfer.id}", params: { include_in_spend: true }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "toggles include_in_spend, which is what the transaction drawer sends" do
      transfer.update!(include_in_spend: false)

      patch "/api/v1/transfers/#{transfer.id}",
            params: { include_in_spend: true }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["include_in_spend"]).to be true
      expect(transfer.reload.include_in_spend).to be true
    end

    it "toggles include_in_spend back off" do
      transfer.update!(include_in_spend: true)

      patch "/api/v1/transfers/#{transfer.id}",
            params: { include_in_spend: false }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(transfer.reload.include_in_spend).to be false
    end

    it "updates the kind and the note" do
      patch "/api/v1/transfers/#{transfer.id}",
            params: { kind: "credit_card_payment", note: "Statement balance" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["kind"]).to eq("credit_card_payment")
      expect(transfer.reload.note).to eq("Statement balance")
    end

    it "rejects a kind outside the enum with a 422" do
      patch "/api/v1/transfers/#{transfer.id}",
            params: { kind: "wire_fraud" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      # enum_param lists the allowed values instead of the opaque
      # inclusion-validation message.
      expect(response.parsed_body["error"]).to include("kind must be one of")
      expect(transfer.reload.kind.serialize).to eq("transfer")
    end

    it "ignores attributes outside the permitted list" do
      original_amount = transfer.amount

      patch "/api/v1/transfers/#{transfer.id}",
            params: { amount: 999_999, include_in_spend: true },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(transfer.reload.amount).to eq(original_amount)
    end

    it "returns 404 for a transfer in another household" do
      other = Current.set(household: create(:household)) do
        their_account = create(:account)
        their_from = create(:cash_transaction, account: their_account)
        their_to   = create(:cash_transaction, account: create(:account))
        Transfer.create!(from_transaction_id: their_from.id, from_transaction_type: "CashTransaction",
                         to_transaction_id:   their_to.id,   to_transaction_type:   "CashTransaction",
                         amount: 25.00)
      end

      patch "/api/v1/transfers/#{other.id}",
            params: { include_in_spend: true }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/transfers/:id" do
    it "clears transfer_id on both sides and destroys the transfer" do
      t = Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                           to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                           amount: 500.00)
      t.confirm!

      expect {
        delete "/api/v1/transfers/#{t.id}", headers: auth_headers
      }.to change(Transfer, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(from_txn.reload.transfer_id).to be_nil
      expect(to_txn.reload.transfer_id).to   be_nil
    end
  end

  describe "POST /api/v1/transfers/:id/dismiss" do
    let(:candidate) do
      Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                       to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                       amount: 500.00)
    end

    it "records the rejected pair and destroys the candidate" do
      candidate
      expect {
        post "/api/v1/transfers/#{candidate.id}/dismiss", headers: auth_headers
      }.to change(Transfer, :count).by(-1).and change(TransferDismissal, :count).by(1)

      expect(response).to have_http_status(:no_content)
      dismissal = TransferDismissal.last
      expect(dismissal.from_transaction_id).to eq(from_txn.id)
      expect(dismissal.to_transaction_id).to eq(to_txn.id)
    end

    it "refuses to dismiss a confirmed transfer" do
      candidate.confirm!

      post "/api/v1/transfers/#{candidate.id}/dismiss", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(Transfer.exists?(candidate.id)).to be true
      expect(TransferDismissal.count).to eq(0)
    end

    it "does not duplicate an existing dismissal for the pair" do
      candidate
      TransferDismissal.create!(
        from_transaction_type: "CashTransaction", from_transaction_id: from_txn.id,
        to_transaction_type:   "CashTransaction", to_transaction_id:   to_txn.id,
        household_id: candidate.household_id
      )

      expect {
        post "/api/v1/transfers/#{candidate.id}/dismiss", headers: auth_headers
      }.to change(Transfer, :count).by(-1).and change(TransferDismissal, :count).by(0)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/transfers with a previously dismissed pair" do
    it "clears the dismissal so future unlink + detection can re-suggest" do
      TransferDismissal.create!(
        from_transaction_type: "CashTransaction", from_transaction_id: from_txn.id,
        to_transaction_type:   "CashTransaction", to_transaction_id:   to_txn.id,
        household_id: create(:api_token).household_id
      )

      expect {
        post "/api/v1/transfers", params: {
          from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
          to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
          amount: 500.00
        }, headers: auth_headers
      }.to change(TransferDismissal, :count).by(-1)

      expect(response).to have_http_status(:created)
    end
  end
end
