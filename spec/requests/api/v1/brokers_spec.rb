require "rails_helper"

RSpec.describe "Api::V1::Brokers", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/brokers" do
    it "returns 401 without authentication" do
      get "/api/v1/brokers"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns brokers sorted by name with account_count" do
      create(:broker, name: "Zebra")
      create(:broker, name: "Alpha")

      get "/api/v1/brokers", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |b| b["name"] }).to eq([ "Alpha", "Zebra" ])
      expect(response.parsed_body.first).to include("account_count")
    end
  end

  describe "GET /api/v1/brokers/:id" do
    it "returns the broker with nested accounts" do
      broker = create(:broker)
      create(:account, broker: broker, name: "Main")

      get "/api/v1/brokers/#{broker.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["name"]).to eq(broker.name)
      expect(body["accounts"].length).to eq(1)
      expect(body["accounts"].first["name"]).to eq("Main")
    end

    it "returns 404 for a nonexistent broker" do
      get "/api/v1/brokers/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/brokers" do
    it "creates and returns the broker" do
      post "/api/v1/brokers", params: { name: "Vanguard" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Vanguard")
    end

    it "returns 422 for a duplicate name" do
      create(:broker, name: "Vanguard")
      post "/api/v1/brokers", params: { name: "Vanguard" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/brokers/:id" do
    it "updates and returns the broker" do
      broker = create(:broker, name: "Old Name")
      patch "/api/v1/brokers/#{broker.id}", params: { name: "New Name" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
    end

    it "returns 404 for a nonexistent broker" do
      patch "/api/v1/brokers/0", params: { name: "x" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/brokers/:id" do
    it "deletes a broker that has no accounts" do
      broker = create(:broker)

      delete "/api/v1/brokers/#{broker.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(Broker.unscoped.where(id: broker.id)).to be_empty
    end

    it "refuses to delete a broker that still has accounts, with a readable message" do
      broker = create(:broker)
      create(:account, broker: broker)

      delete "/api/v1/brokers/#{broker.id}", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Cannot delete a broker that still has accounts.")
      expect(Broker.unscoped.where(id: broker.id)).to be_present
    end

    it "returns 404 for a nonexistent broker" do
      delete "/api/v1/brokers/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a broker in another household" do
      other = Current.set(household: create(:household)) { create(:broker) }

      delete "/api/v1/brokers/#{other.id}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(Broker.unscoped.where(id: other.id)).to be_present
    end

    it "returns 401 without authentication" do
      broker = create(:broker)
      delete "/api/v1/brokers/#{broker.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
