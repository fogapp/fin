require "rails_helper"

RSpec.describe "Api::V1::Loans", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/loans" do
    it "returns 401 without authentication" do
      get "/api/v1/loans"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns loans newest first with the computed payment stats the list renders" do
      create(:loan, name: "Older", created_at: 2.days.ago)
      create(:loan, name: "Newer", created_at: 1.day.ago)

      get "/api/v1/loans", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |l| l["name"] }).to eq([ "Newer", "Older" ])
      expect(body.first).to include(
        "original_principal", "interest_rate", "monthly_payment",
        "current_balance", "principal_paid", "interest_paid", "payments_count"
      )
    end

    it "does not leak loans belonging to another household" do
      create(:loan, name: "Mine")
      Current.set(household: create(:household)) { create(:loan, name: "Theirs") }

      get "/api/v1/loans", headers: auth_headers

      expect(response.parsed_body.map { |l| l["name"] }).to eq([ "Mine" ])
    end
  end

  describe "GET /api/v1/loans/:id" do
    it "returns the loan with its amortization schedule and linked transactions" do
      account = create(:account)
      loan    = create(:loan, account: account)
      create(:cash_transaction, account: account, loan: loan,
                                description: "Mortgage payment", transaction_date: Date.current)

      get "/api/v1/loans/#{loan.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(loan.id)
      expect(body["amortization_schedule"]).to be_an(Array)
      expect(body["linked_transactions"].map { |t| t["description"] }).to eq([ "Mortgage payment" ])
    end

    it "returns 404 for a loan in another household" do
      other = Current.set(household: create(:household)) { create(:loan) }

      get "/api/v1/loans/#{other.id}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/loans" do
    it "creates the loan and returns 201 with the serialized body" do
      expect {
        post "/api/v1/loans",
             params: { name: "Car", loan_type: "auto", original_principal: 30_000,
                       interest_rate: 5.5, term_months: 60, start_date: Date.current.to_s,
                       status: "active" },
             headers: auth_headers, as: :json
      }.to change { Loan.unscoped.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Car")
      expect(Loan.unscoped.order(:created_at).last.household_id).to eq(token.household_id)
    end

    it "returns 422 when a required attribute is missing" do
      post "/api/v1/loans", params: { lender: "Chase" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end

    it "rejects an enum value outside the contract" do
      post "/api/v1/loans",
           params: { name: "X", loan_type: "spaceship", original_principal: 1, interest_rate: 1,
                     term_months: 12, start_date: Date.current.to_s },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/loans/:id" do
    it "updates the loan and returns the reloaded body" do
      loan = create(:loan, name: "Old", status: "active")

      patch "/api/v1/loans/#{loan.id}",
            params: { name: "New", status: "paid_off" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("name" => "New", "status" => "paid_off")
      expect(loan.reload.name).to eq("New")
    end

    it "records the escrow in a mortgage payment and returns the principal-and-interest split" do
      loan = create(:loan, monthly_payment: 2500)

      patch "/api/v1/loans/#{loan.id}",
            params: { escrow_property_tax: 350, escrow_insurance: 120, escrow_other: 30 },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "monthly_payment" => 2500.0, "entered_monthly_payment" => 2500.0, "principal_and_interest_payment" => 2000.0,
        "escrow_property_tax" => 350.0, "escrow_insurance" => 120.0, "escrow_other" => 30.0,
        "escrow_payment" => 500.0
      )
    end

    it "reports no entered payment when the payment is computed" do
      loan = create(:loan)

      get "/api/v1/loans/#{loan.id}", headers: auth_headers

      expect(response.parsed_body["entered_monthly_payment"]).to be_nil
      expect(response.parsed_body["monthly_payment"]).to be > 0
    end

    it "links a loan to an account and a merchant" do
      loan     = create(:loan)
      account  = create(:account)
      merchant = create(:merchant)

      patch "/api/v1/loans/#{loan.id}",
            params: { account_id: account.id, merchant_id: merchant.id },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("account_id" => account.id, "merchant_id" => merchant.id)
    end

    it "returns 404 for a loan in another household" do
      other = Current.set(household: create(:household)) { create(:loan) }

      patch "/api/v1/loans/#{other.id}", params: { name: "Hijacked" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/loans/:id" do
    it "destroys the loan and nullifies its linked transactions" do
      account = create(:account)
      loan    = create(:loan, account: account)
      txn     = create(:cash_transaction, account: account, loan: loan)

      delete "/api/v1/loans/#{loan.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(Loan.unscoped.where(id: loan.id)).to be_empty
      expect(txn.reload.loan_id).to be_nil
    end

    it "returns 404 for a loan in another household" do
      other = Current.set(household: create(:household)) { create(:loan) }

      delete "/api/v1/loans/#{other.id}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(Loan.unscoped.where(id: other.id)).to be_present
    end
  end

  describe "GET /api/v1/loans/:id/candidate_transactions" do
    it "returns unlinked transactions from the loan's account, newest first" do
      account = create(:account)
      loan    = create(:loan, account: account)
      create(:cash_transaction, account: account, loan: loan, description: "Already linked")
      create(:cash_transaction, account: account, description: "Older", transaction_date: Date.current - 2)
      create(:cash_transaction, account: account, description: "Newer", transaction_date: Date.current - 1)

      get "/api/v1/loans/#{loan.id}/candidate_transactions", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |t| t["description"] }).to eq([ "Newer", "Older" ])
      expect(body.first).to include("id", "transaction_date", "amount", "account_name")
    end

    it "excludes transactions from other accounts once the loan is linked to one" do
      account = create(:account)
      loan    = create(:loan, account: account)
      create(:cash_transaction, account: create(:account), description: "Elsewhere")

      get "/api/v1/loans/#{loan.id}/candidate_transactions", headers: auth_headers

      expect(response.parsed_body.map { |t| t["description"] }).not_to include("Elsewhere")
    end

    it "returns 401 without authentication" do
      loan = create(:loan)
      get "/api/v1/loans/#{loan.id}/candidate_transactions"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
