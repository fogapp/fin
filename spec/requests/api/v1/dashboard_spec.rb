require "rails_helper"

RSpec.describe "Api::V1::Dashboard", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/dashboard" do
    it "returns 401 without authentication" do
      get "/api/v1/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the full dashboard payload" do
      get "/api/v1/dashboard", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "stats", "portfolio_chart", "allocation",
        "income_series", "activity_chart", "compact_stats", "recent_transactions"
      )
    end

    # Each linked ribbon item must show the number its stat page shows.
    it "computes the linked ribbon items with their stat definitions" do
      link = lambda do |txn|
        transfer = create(:transfer, :confirmed, amount: txn.amount.abs,
                          from_transaction_id: txn.id, from_transaction_type: "CashTransaction",
                          counterparty_account_id: create(:account, kind: "external").id)
        txn.update!(transfer: transfer)
      end

      create(:cash_transaction, :sale, amount: -40.00)
      create(:cash_transaction, :sale, amount: -20.00)
      create(:cash_transaction, :return, amount: 10.00)
      # A card autopayment — card imports type these as Returns.
      link.call(create(:cash_transaction, :return, amount: 5_000.00, description: "AUTOMATIC PAYMENT - THANK"))
      # A transfer-linked bank debit typed "Sale".
      link.call(create(:cash_transaction, :bank, transaction_type: "Sale", amount: -10_000.00))
      create(:cash_transaction, :bank, :credit, amount: 3_000.00)

      get "/api/v1/dashboard", headers: auth_headers

      month = Date.current.beginning_of_month
      stat  = ->(klass) { klass.new.series(from: month, to: Date.current)[month] }
      cs    = response.parsed_body["compact_stats"]
      expect(cs["spend"]).to eq(50.0).and eq(stat.(Metrics::Definitions::MonthlySpend))
      expect(cs["income"]).to eq(3_000.0).and eq(stat.(Metrics::Definitions::MonthlyIncome))
      expect(cs["cc_count"]).to eq(3).and eq(stat.(Metrics::Definitions::CcTransactionCount))
      expect(cs["cc_avg"]).to eq(16.67).and eq(stat.(Metrics::Definitions::CcAvgTransaction))
    end

    it "accepts an optional broker_id filter" do
      broker = create(:broker)
      get "/api/v1/dashboard", params: { broker_id: broker.id }, headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a nonexistent broker_id" do
      get "/api/v1/dashboard", params: { broker_id: 0 }, headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
