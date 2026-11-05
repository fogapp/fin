require "rails_helper"

# Endpoints driven by the manual investment-transaction drawer + the
# "reprocess" button on the txn list. Not previously covered.
RSpec.describe "Api::V1::InvestmentTransactions create + reprocess", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account) }
  let(:security)     { create(:security, ticker: "AAPL") }
  let!(:purchase_type) { create(:transaction_type, :purchase) }
  let!(:sale_type)     { create(:transaction_type, :sale) }
  let!(:dividend_type) { create(:transaction_type, :dividend) }

  describe "POST /api/v1/investment_transactions" do
    it "creates a manual Purchase txn and computes cost_usd from quantity*price" do
      expect {
        post "/api/v1/investment_transactions",
             params: { transaction_type: "Purchase",
                       account_id: account.id, security_id: security.id,
                       trade_date: "2026-01-15",
                       quantity: 10, price_usd: 150, amount_usd: 1500,
                       description: "Manual buy" },
             headers: auth_headers, as: :json
      }.to change(InvestmentTransaction, :count).by(1)
        .and change(PositionSnapshot, :count).by(1)

      expect(response).to have_http_status(:created)
      txn = InvestmentTransaction.last
      expect(txn.transaction_type).to eq(purchase_type)
      expect(txn.cost_usd.to_f).to    eq(1500.0)
      expect(txn.amount_usd.to_f).to  eq(1500.0)
      expect(txn.local_currency).to   eq("USD")
      expect(txn.source_row_hash).to be_present
      expect(txn.income_usd).to be_nil
    end

    it "sets income_usd (not cost_usd) for Dividend transactions" do
      post "/api/v1/investment_transactions",
           params: { transaction_type: "Dividend",
                     account_id: account.id, security_id: security.id,
                     trade_date: "2026-02-01",
                     amount_usd: 42.50, description: "AAPL dividend" },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      txn = InvestmentTransaction.last
      expect(txn.transaction_type).to eq(dividend_type)
      expect(txn.income_usd.to_f).to eq(42.50)
      expect(txn.cost_usd).to be_nil
    end

    it "creates without a security when the txn doesn't need one" do
      post "/api/v1/investment_transactions",
           params: { transaction_type: "Dividend",
                     account_id: account.id, trade_date: "2026-02-01",
                     amount_usd: 1.00 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(InvestmentTransaction.last.security).to be_nil
    end

    it "returns 404 for an unknown transaction_type category" do
      expect {
        post "/api/v1/investment_transactions",
             params: { transaction_type: "BogusCategory",
                       account_id: account.id, trade_date: "2026-01-01",
                       amount_usd: 1 },
             headers: auth_headers, as: :json
      }.not_to change(InvestmentTransaction, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/investment_transactions/:id/reprocess" do
    it "recomputes the position snapshot for a purchase txn" do
      create(:market_price, security: security, close: 200.0)
      txn = create(:investment_transaction, security: security, account: account,
                   transaction_type: purchase_type,
                   quantity: 10, cost_usd: 1_000, amount_usd: 1_000)

      expect {
        post "/api/v1/investment_transactions/#{txn.id}/reprocess", headers: auth_headers
      }.to change(PositionSnapshot, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to       eq("updated")
      expect(body["as_of_date"]).to   eq(Date.current.to_s)
      expect(body["market_value"]).to eq(2000.0)
    end

    it "returns skipped for income-type transactions" do
      txn = create(:investment_transaction, security: security, account: account,
                   transaction_type: dividend_type)

      post "/api/v1/investment_transactions/#{txn.id}/reprocess", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "skipped",
                                         "reason" => "not a purchase or sale")
    end

    it "returns 404 for an unknown id" do
      post "/api/v1/investment_transactions/00000000-0000-0000-0000-000000000000/reprocess",
           headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
