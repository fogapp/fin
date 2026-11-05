require "rails_helper"

RSpec.describe "Api::V1::ApiTokens", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/api_tokens" do
    it "returns the current user's tokens ordered by most recent first" do
      create(:api_token, name: "Old", created_at: 2.days.ago)
      create(:api_token, name: "New", created_at: 1.day.ago)

      get "/api/v1/api_tokens", headers: auth_headers
      expect(response).to have_http_status(:ok)
      names = response.parsed_body.map { |t| t["name"] }
      expect(names.index("New")).to be < names.index("Old")
    end

    it "does NOT leak tokens belonging to a different user in the same household (A1 regression)" do
      other_user = User.create!(email: "other@example.com", name: "Other")
      HouseholdMembership.find_or_create_by!(user: other_user, household: Current.household) { |m| m.role = "member" }
      create(:api_token, user: other_user, household: Current.household, name: "Other-User Token")

      get "/api/v1/api_tokens", headers: auth_headers
      names = response.parsed_body.map { |t| t["name"] }
      expect(names).not_to include("Other-User Token")
    end

    it "does NOT leak tokens belonging to a different household (A1 regression)" do
      other_household = Household.create!(name: "Other House")
      other_user      = User.create!(email: "outsider@example.com", name: "Outsider")
      HouseholdMembership.create!(user: other_user, household: other_household, role: "admin")
      create(:api_token, user: other_user, household: other_household, name: "Other-Household Token")

      get "/api/v1/api_tokens", headers: auth_headers
      names = response.parsed_body.map { |t| t["name"] }
      expect(names).not_to include("Other-Household Token")
    end

    it "includes expected fields but not the raw token value" do
      get "/api/v1/api_tokens", headers: auth_headers
      body = response.parsed_body.first
      expect(body.keys).to include("id", "name", "scope", "last_used_at", "expires_at", "created_at")
      expect(body.keys).not_to include("token")
    end

    it "requires authentication" do
      get "/api/v1/api_tokens"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/api_tokens" do
    it "returns 401 without authentication" do
      post "/api/v1/api_tokens", params: { name: "CLI" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a token and returns the raw value exactly once, at creation" do
      headers = auth_headers
      expect {
        post "/api/v1/api_tokens", params: { name: "CLI" }, headers: headers, as: :json
      }.to change(ApiToken, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("CLI")
      expect(body["token"]).to be_present

      # The raw token is never returned again by the listing.
      get "/api/v1/api_tokens", headers: headers
      expect(response.parsed_body.map(&:keys).flatten).not_to include("token")
    end

    it "issues a token that actually authenticates subsequent requests" do
      post "/api/v1/api_tokens", params: { name: "CLI" }, headers: auth_headers, as: :json
      raw = response.parsed_body["token"]

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{raw}" }

      expect(response).to have_http_status(:ok)
    end

    it "scopes the new token to the authenticated user and household" do
      post "/api/v1/api_tokens", params: { name: "CLI" }, headers: auth_headers, as: :json

      created = ApiToken.unscoped.find(response.parsed_body["id"])
      expect(created.user_id).to eq(token.user_id)
      expect(created.household_id).to eq(token.household_id)
      expect(created.session).to be false
    end

    it "stores an expiry when one is supplied" do
      expires = 30.days.from_now.change(usec: 0)
      post "/api/v1/api_tokens", params: { name: "Temp", expires_at: expires.iso8601 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Time.zone.parse(response.parsed_body["expires_at"])).to be_within(1.second).of(expires)
    end

    it "creates an unnamed token when name is blank" do
      post "/api/v1/api_tokens", params: { name: "" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to be_nil
    end
  end

  describe "DELETE /api/v1/api_tokens/:id" do
    it "destroys the current user's token" do
      headers   = auth_headers          # materialize auth token before measuring count
      to_delete = create(:api_token)
      expect {
        delete "/api/v1/api_tokens/#{to_delete.id}", headers: headers
      }.to change(ApiToken, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for a missing token" do
      delete "/api/v1/api_tokens/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to destroy another user's token in the same household (A1 regression)" do
      other_user = User.create!(email: "other@example.com", name: "Other")
      HouseholdMembership.find_or_create_by!(user: other_user, household: Current.household) { |m| m.role = "member" }
      other_token = create(:api_token, user: other_user, household: Current.household)

      headers = auth_headers
      expect {
        delete "/api/v1/api_tokens/#{other_token.id}", headers: headers
      }.not_to change(ApiToken, :count)

      expect(response).to have_http_status(:not_found)
      # HouseholdScoped default-scopes ApiToken now; check via unscoped.
      expect(ApiToken.unscoped.exists?(other_token.id)).to be true
    end

    it "refuses to destroy a token in a different household (A1 regression)" do
      other_household = Household.create!(name: "Other House")
      other_user      = User.create!(email: "outsider@example.com", name: "Outsider")
      HouseholdMembership.create!(user: other_user, household: other_household, role: "admin")
      other_token = create(:api_token, user: other_user, household: other_household)

      headers = auth_headers
      expect {
        delete "/api/v1/api_tokens/#{other_token.id}", headers: headers
      }.not_to change(ApiToken, :count)

      expect(response).to have_http_status(:not_found)
      # HouseholdScoped default-scopes ApiToken now; check via unscoped.
      expect(ApiToken.unscoped.exists?(other_token.id)).to be true
    end
  end
end
