require "rails_helper"

RSpec.describe "Api::V1::Me", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/me" do
    it "returns 401 without authentication" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user and household with the membership role" do
      get "/api/v1/me", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["user"]).to include("id", "email", "name")
      expect(body["household"]).to include("id", "name", "role")
      expect(body["household"]["role"]).to eq("admin")
    end

    it "returns a nil role when the user has no membership in the active household" do
      other_household = Household.create!(name: "Other")
      other_token     = create(:api_token, household: other_household)

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
      expect(response.parsed_body["household"]["role"]).to be_nil
    end
  end
end
