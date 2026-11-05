require "rails_helper"

RSpec.describe "Api::V1::Tags", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/tags" do
    it "returns 401 without authentication" do
      get "/api/v1/tags"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns all tags sorted by name with transaction_count and total_spend" do
      create(:tag, name: "zebra")
      create(:tag, name: "apple")

      get "/api/v1/tags", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |t| t["name"] }).to eq([ "apple", "zebra" ])
      expect(response.parsed_body.first).to include("transaction_count", "total_spend")
    end
  end

  describe "GET /api/v1/tags/:id" do
    it "returns 401 without authentication" do
      tag = create(:tag)
      get "/api/v1/tags/#{tag.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the tag with totals and by_category breakdown" do
      tag = create(:tag)
      txn = create(:cash_transaction, :credit_card, :sale, amount: -30.0)
      txn.tags << tag

      get "/api/v1/tags/#{tag.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["name"]).to eq(tag.name)
      expect(body["total_spend"]).to eq(30.0)
      expect(body).to include("total_count", "total_returns", "by_category")
    end

    it "returns 404 for a nonexistent tag" do
      get "/api/v1/tags/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/tags" do
    it "returns 401 without authentication" do
      post "/api/v1/tags", params: { name: "travel" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates and returns the tag" do
      post "/api/v1/tags", params: { name: "  Travel  " }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Travel")
    end

    it "returns 422 for a duplicate name" do
      create(:tag, name: "travel")
      post "/api/v1/tags", params: { name: "travel" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/tags/:id" do
    it "returns 401 without authentication" do
      tag = create(:tag)
      delete "/api/v1/tags/#{tag.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "destroys the tag and returns 204" do
      tag = create(:tag)
      expect {
        delete "/api/v1/tags/#{tag.id}", headers: auth_headers
      }.to change(Tag, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for a nonexistent tag" do
      delete "/api/v1/tags/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
