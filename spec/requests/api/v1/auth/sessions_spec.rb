require "rails_helper"

RSpec.describe "Session switching", type: :request do
  let(:user)      { Current.user }
  let(:household) { Current.household }
  let(:token)     { create(:api_token, user: user, household: household, name: "T") }
  let(:headers)   { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/auth/switch_household" do
    it "mints a new token for a household the user is a member of" do
      other = create(:household, name: "Other")
      create(:household_membership, user: user, household: other, role: "member")
      headers # eager-eval so the let-created token doesn't pollute the count

      expect {
        post "/api/v1/auth/switch_household", params: { household_id: other.id }, headers: headers
      }.to change(ApiToken.unscoped, :count).by(1)  # new token is in the other household
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body.dig("household", "id")).to eq(other.id)
      expect(body.dig("household", "role")).to eq("member")
    end

    it "refuses to switch to a household the user is not a member of" do
      stranger = create(:household, name: "Stranger")
      post "/api/v1/auth/switch_household", params: { household_id: stranger.id }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
