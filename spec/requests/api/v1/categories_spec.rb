require "rails_helper"

RSpec.describe "Api::V1::Categories", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/categories" do
    it "returns 401 without authentication" do
      get "/api/v1/categories"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns categories sorted by name with transaction_count" do
      create(:category, name: "Zebra")
      create(:category, name: "Apple")

      get "/api/v1/categories", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |c| c["name"] }).to eq([ "Apple", "Zebra" ])
      expect(response.parsed_body.first).to include("transaction_count")
    end
  end

  describe "GET /api/v1/categories/:id" do
    it "returns the category with totals and series" do
      category = create(:category)
      create(:cash_transaction, :credit_card, :sale, category: category, amount: -20.0)

      get "/api/v1/categories/#{category.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["name"]).to eq(category.name)
      expect(body["total_spend"]).to eq(20.0)
      expect(body).to include("total_count", "total_returns", "by_merchant", "monthly_spend")
    end

    it "returns 404 for a nonexistent category" do
      get "/api/v1/categories/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/categories" do
    it "creates and returns the category" do
      post "/api/v1/categories", params: { name: "Dining" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Dining")
    end

    it "returns 422 for a duplicate name" do
      create(:category, name: "Dining")
      post "/api/v1/categories", params: { name: "Dining" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/categories/:id" do
    it "updates and returns the category" do
      category = create(:category, name: "Old")
      patch "/api/v1/categories/#{category.id}", params: { name: "New" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New")
    end

    it "returns 404 for a nonexistent category" do
      patch "/api/v1/categories/0", params: { name: "x" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "updates and serializes the charitable flag" do
      category = create(:category)
      patch "/api/v1/categories/#{category.id}", params: { charitable: true },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["charitable"]).to be(true)
      expect(category.reload.charitable).to be(true)
    end
  end

  describe "DELETE /api/v1/categories/:id" do
    it "destroys the category and returns 204" do
      category = create(:category)
      delete "/api/v1/categories/#{category.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(Category.exists?(category.id)).to be false
    end

    it "returns 404 for a nonexistent category" do
      delete "/api/v1/categories/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
