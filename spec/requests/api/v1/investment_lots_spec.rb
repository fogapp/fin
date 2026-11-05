require "rails_helper"

RSpec.describe "Api::V1::InvestmentLots", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:security)     { create(:security) }
  let(:account)      { create(:account) }

  describe "GET /api/v1/investment_lots" do
    it "returns lots scoped to the requested security" do
      lot   = create(:investment_lot, security: security, account: account, quantity: 5, cost_basis: 500)
      _othr = create(:investment_lot, security: create(:security))

      get "/api/v1/investment_lots", params: { security_id: security.id }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first).to include(
        "id" => lot.id, "account_name" => account.name, "quantity" => 5.0, "cost_basis" => 500.0
      )
    end
  end

  describe "POST /api/v1/investment_lots" do
    it "creates a lot" do
      expect {
        post "/api/v1/investment_lots",
             params: { security_id: security.id, account_id: account.id,
                       acquired_date: "2026-01-15", quantity: 10, cost_basis: 1234.56 },
             headers: auth_headers, as: :json
      }.to change(InvestmentLot, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["quantity"]).to eq(10.0)
      expect(body["cost_basis"]).to eq(1234.56)
      expect(body["unit_cost"]).to eq(123.456)
    end
  end

  describe "PATCH /api/v1/investment_lots/:id" do
    let!(:lot) { create(:investment_lot, security: security, account: account, quantity: 5, cost_basis: 100) }

    it "updates the lot" do
      patch "/api/v1/investment_lots/#{lot.id}",
            params: { quantity: 8, cost_basis: 200 },
            headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["quantity"]).to eq(8.0)
      expect(response.parsed_body["cost_basis"]).to eq(200.0)
    end
  end

  describe "DELETE /api/v1/investment_lots/:id" do
    let!(:lot) { create(:investment_lot, security: security) }

    it "destroys the lot" do
      expect {
        delete "/api/v1/investment_lots/#{lot.id}", headers: auth_headers
      }.to change(InvestmentLot, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/investment_lots/generate" do
    let(:purchase_type) { create(:transaction_type, :purchase) }
    let!(:purchase) do
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: purchase_type,
             trade_date: Date.new(2026, 1, 1),
             quantity: 10, amount_usd: 500, cost_usd: 500)
    end

    context "without commit" do
      it "returns a preview without persisting" do
        expect {
          post "/api/v1/investment_lots/generate",
               params: { security_id: security.id },
               headers: auth_headers, as: :json
        }.not_to change(InvestmentLot, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_an(Array)
        expect(response.parsed_body.first).to include("quantity", "cost_basis")
      end
    end

    context "with commit: true" do
      it "persists lots and returns 201" do
        expect {
          post "/api/v1/investment_lots/generate",
               params: { security_id: security.id, commit: true },
               headers: auth_headers, as: :json
        }.to change(InvestmentLot, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it "returns 409 when lots already exist and replace is not set" do
        create(:investment_lot, security: security)

        post "/api/v1/investment_lots/generate",
             params: { security_id: security.id, commit: true },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body["error"]).to eq("lots_exist")
        expect(response.parsed_body["count"]).to be >= 1
      end

      it "replaces existing lots when replace=true" do
        old = create(:investment_lot, security: security)

        post "/api/v1/investment_lots/generate",
             params: { security_id: security.id, commit: true, replace: true },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(InvestmentLot.exists?(old.id)).to be false
      end
    end
  end
end
