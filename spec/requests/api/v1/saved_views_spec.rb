require "rails_helper"

RSpec.describe "Api::V1::SavedViews", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/saved_views" do
    it "returns 401 without authentication" do
      get "/api/v1/saved_views"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns an array of saved views" do
      create(:saved_view, name: "My View")

      get "/api/v1/saved_views", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
      expect(response.parsed_body.first["name"]).to eq("My View")
    end

    it "returns empty array when no saved views exist" do
      get "/api/v1/saved_views", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "returns saved views with expected keys" do
      create(:saved_view)

      get "/api/v1/saved_views", headers: auth_headers
      expect(response.parsed_body.first).to include("id", "name", "conditions", "match_all", "created_at")
    end
  end

  describe "POST /api/v1/saved_views" do
    let(:valid_params) do
      {
        name:       "High Spend",
        conditions: [ { field: "amount", operator: "greater_than", value: "100" } ],
        match_all:  true
      }
    end

    it "returns 401 without authentication" do
      post "/api/v1/saved_views", params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a saved view and returns 201" do
      expect {
        post "/api/v1/saved_views", params: valid_params, headers: auth_headers, as: :json
      }.to change(SavedView, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("High Spend")
      expect(body["conditions"]).to be_an(Array)
      expect(body["match_all"]).to be true
    end

    it "stores conditions as JSON" do
      post "/api/v1/saved_views", params: valid_params, headers: auth_headers, as: :json
      view = SavedView.last
      parsed = JSON.parse(view.filter_params)
      expect(parsed["conditions"]).to be_an(Array)
    end
  end

  describe "PATCH /api/v1/saved_views/:id" do
    let!(:view) { create(:saved_view, name: "Old Name") }

    it "returns 401 without authentication" do
      patch "/api/v1/saved_views/#{view.id}", params: { name: "New Name" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "updates name and returns 200" do
      patch "/api/v1/saved_views/#{view.id}",
            params: { name: "New Name" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
    end

    it "updates conditions" do
      new_conditions = [ { field: "description", operator: "contains", value: "Amazon" } ]
      patch "/api/v1/saved_views/#{view.id}",
            params: { name: view.name, conditions: new_conditions },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["conditions"]).to be_an(Array)
    end
  end

  describe "DELETE /api/v1/saved_views/:id" do
    let!(:view) { create(:saved_view) }

    it "returns 401 without authentication" do
      delete "/api/v1/saved_views/#{view.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "destroys the saved view and returns 204" do
      expect {
        delete "/api/v1/saved_views/#{view.id}", headers: auth_headers
      }.to change(SavedView, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
