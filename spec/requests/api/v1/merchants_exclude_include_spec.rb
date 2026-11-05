require "rails_helper"

# POST /api/v1/merchants/:id/exclude and /include — toggles excluded
# status for the merchant. Cashflow's spend scope filters out excluded
# merchants, so this is the user-visible effect that matters.
RSpec.describe "Api::V1::Merchants exclude / include", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account) }

  describe "POST /api/v1/merchants/:id/exclude" do
    it "marks the merchant excluded and removes it from cashflow's spend scope" do
      merchant = create(:merchant, name: "Charge-off", excluded: false)
      create(:cash_transaction, :credit_card, account: account, merchant: merchant,
             transaction_type: "Sale", amount: -100.00,
             transaction_date: Date.current)

      get "/api/v1/cashflow", headers: auth_headers
      ytd_before = response.parsed_body["summary"]["ytd_spend"]

      post "/api/v1/merchants/#{merchant.id}/exclude", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(merchant.reload.excluded).to be true

      get "/api/v1/cashflow", headers: auth_headers
      ytd_after = response.parsed_body["summary"]["ytd_spend"]
      expect(ytd_after).to eq((ytd_before - 100.0).round(2))
    end

    it "returns 404 for an unknown merchant" do
      post "/api/v1/merchants/00000000-0000-0000-0000-000000000000/exclude",
           headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/merchants/:id/include" do
    it "marks a previously-excluded merchant active again" do
      merchant = create(:merchant, name: "Reinstated", excluded: true)

      post "/api/v1/merchants/#{merchant.id}/include", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(merchant.reload.excluded).to be false
    end
  end
end
