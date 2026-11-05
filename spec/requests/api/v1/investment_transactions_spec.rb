require "rails_helper"

RSpec.describe "Api::V1::InvestmentTransactions", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/investment_transactions" do
    it "returns 401 without authentication" do
      get "/api/v1/investment_transactions"
      expect(response).to have_http_status(:unauthorized)
    end

    context "with valid token" do
      it "returns 200 with an array of transactions" do
        create(:investment_transaction)

        get "/api/v1/investment_transactions", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_an(Array)
        expect(response.parsed_body.length).to eq(1)
      end

      it "returns empty array when no transactions exist" do
        get "/api/v1/investment_transactions", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end

      it "filters by account_id param" do
        account1 = create(:account)
        account2 = create(:account)
        t1 = create(:investment_transaction, account: account1)
        create(:investment_transaction, account: account2)

        get "/api/v1/investment_transactions", params: { account_id: account1.id }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        ids = response.parsed_body.map { |t| t["id"] }
        expect(ids).to contain_exactly(t1.id)
      end

      it "respects the limit param" do
        create_list(:investment_transaction, 5)

        get "/api/v1/investment_transactions", params: { limit: 2 }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "clamps negative limit and offset instead of erroring" do
        create_list(:investment_transaction, 3)

        get "/api/v1/investment_transactions", params: { limit: -1, offset: -5 }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
      end

      it "pages with offset" do
        newest = create(:investment_transaction, trade_date: 1.day.ago)
        older  = create(:investment_transaction, trade_date: 2.days.ago)

        get "/api/v1/investment_transactions", params: { limit: 1, offset: 1 }, headers: auth_headers
        expect(response.parsed_body.map { |t| t["id"] }).to eq([ older.id ])
        expect(newest).to be_present
      end

      it "returns every row when limit=all" do
        create_list(:investment_transaction, 3)

        get "/api/v1/investment_transactions", params: { limit: "all" }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(3)
      end

      it "defaults to a limit of 200" do
        create_list(:investment_transaction, 3)

        get "/api/v1/investment_transactions", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(3)
      end

      it "returns transactions sorted by trade_date descending" do
        t1 = create(:investment_transaction, trade_date: 3.days.ago)
        t2 = create(:investment_transaction, trade_date: 1.day.ago)

        get "/api/v1/investment_transactions", headers: auth_headers
        ids = response.parsed_body.map { |t| t["id"] }
        expect(ids).to eq([ t2.id, t1.id ])
      end
    end
  end
end
