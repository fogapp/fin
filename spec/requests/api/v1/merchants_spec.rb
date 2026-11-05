require "rails_helper"

RSpec.describe "Api::V1::Merchants", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/merchants" do
    it "returns 401 without authentication" do
      get "/api/v1/merchants"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns merchants sorted by name with transaction_count" do
      create(:merchant, name: "Zebra")
      create(:merchant, name: "Apple")

      get "/api/v1/merchants", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |m| m["name"] }).to eq([ "Apple", "Zebra" ])
      expect(response.parsed_body.first).to include("transaction_count")
    end
  end

  describe "GET /api/v1/merchants/:id" do
    it "returns the merchant with monthly series" do
      merchant = create(:merchant)

      get "/api/v1/merchants/#{merchant.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["name"]).to eq(merchant.name)
      expect(body).to include("monthly_spend", "monthly_counts", "monthly_income")
    end

    it "returns 404 for a nonexistent merchant" do
      get "/api/v1/merchants/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/merchants" do
    it "creates and returns the merchant" do
      category = create(:category)
      post "/api/v1/merchants",
           params: { name: "Starbucks", category_id: category.id },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Starbucks")
    end

    it "returns 422 when invalid" do
      post "/api/v1/merchants", params: { name: "" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/merchants/:id" do
    it "updates and returns the merchant" do
      merchant = create(:merchant)
      patch "/api/v1/merchants/#{merchant.id}",
            params: { name: "Updated Name" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("Updated Name")
    end

    it "returns 404 for a nonexistent merchant" do
      patch "/api/v1/merchants/0", params: { name: "x" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/merchants/:id" do
    it "destroys the merchant and returns 204" do
      merchant = create(:merchant)
      delete "/api/v1/merchants/#{merchant.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(Merchant.exists?(merchant.id)).to be false
    end

    it "returns 404 for a nonexistent merchant" do
      delete "/api/v1/merchants/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
