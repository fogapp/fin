require "rails_helper"

RSpec.describe "Invites", type: :request do
  # household_context.rb already sets Current.user as an admin of Current.household.
  let(:household) { Current.household }
  let(:user)      { Current.user }
  let(:token)     { create(:api_token, user: user, household: household, name: "T") }
  let(:headers)   { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/invites" do
    it "creates an invite when called by an admin" do
      post "/api/v1/invites", params: { role: "member", expires_in_days: 14 }, headers: headers
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["code"]).to be_present
      expect(body["role"]).to eq("member")
      expect(body.dig("household", "id")).to eq(household.id)
      expect(body["accept_url"]).to include("/register?invite=#{body['code']}")
    end

    it "forbids non-admin members" do
      HouseholdMembership.where(user: user, household: household).update_all(role: "member")
      post "/api/v1/invites", params: { role: "member" }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/invites/:code (public)" do
    it "returns household info for a usable invite" do
      invite = create(:invite_code, household: household, role: "admin")
      get "/api/v1/invites/#{invite.code}"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["role"]).to eq("admin")
      expect(body.dig("household", "name")).to eq(household.name)
    end

    it "returns 410 for a used invite" do
      invite = create(:invite_code, household: household, used_at: 1.minute.ago, used_by: create(:user))
      get "/api/v1/invites/#{invite.code}"
      expect(response).to have_http_status(:gone)
    end

    it "returns 410 for an expired invite" do
      invite = create(:invite_code, household: household, expires_at: 1.day.ago)
      get "/api/v1/invites/#{invite.code}"
      expect(response).to have_http_status(:gone)
    end

    it "returns 404 for an unknown code" do
      get "/api/v1/invites/nope-nope"
      expect(response).to have_http_status(:not_found)
    end
  end
end
