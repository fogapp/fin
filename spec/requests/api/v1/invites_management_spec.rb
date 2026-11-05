require "rails_helper"

RSpec.describe "Invites management (list + revoke)", type: :request do
  let(:admin)     { Current.user }
  let(:household) { Current.household }
  let(:token)     { create(:api_token, user: admin, household: household, name: "T") }
  let(:headers)   { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/invites" do
    it "lists usable invites for the active household (admin-only)" do
      usable  = create(:invite_code, household: household)
      _used   = create(:invite_code, household: household, used_at: 1.day.ago, used_by: create(:user))
      _expired = create(:invite_code, household: household, expires_at: 1.day.ago)

      get "/api/v1/invites", headers: headers
      expect(response).to have_http_status(:ok)
      codes = response.parsed_body.map { |i| i["code"] }
      expect(codes).to eq([ usable.code ])
    end

    it "forbids non-admins" do
      HouseholdMembership.where(user: admin, household: household).update_all(role: "member")
      get "/api/v1/invites", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/invites/:code" do
    it "revokes an unused invite" do
      invite = create(:invite_code, household: household)
      expect {
        delete "/api/v1/invites/#{invite.code}", headers: headers
      }.to change(InviteCode, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "refuses to revoke a used invite" do
      invite = create(:invite_code, household: household, used_at: 1.day.ago, used_by: create(:user))
      delete "/api/v1/invites/#{invite.code}", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
