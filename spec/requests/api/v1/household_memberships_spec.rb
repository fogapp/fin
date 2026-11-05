require "rails_helper"

RSpec.describe "HouseholdMemberships", type: :request do
  let(:admin)     { Current.user }
  let(:household) { Current.household }
  let(:token)     { create(:api_token, user: admin, household: household, name: "T") }
  let(:headers)   { { "Authorization" => "Bearer #{token.raw_token}" } }

  let!(:member_user) { create(:user, email: "member@example.com") }
  let!(:member_membership) do
    create(:household_membership, user: member_user, household: household, role: "member")
  end

  describe "GET /api/v1/household_memberships" do
    it "lists all members of the active household" do
      get "/api/v1/household_memberships", headers: headers
      expect(response).to have_http_status(:ok)
      emails = response.parsed_body.map { |m| m.dig("user", "email") }
      expect(emails).to include(admin.email, "member@example.com")
    end
  end

  describe "PATCH /api/v1/household_memberships/:id" do
    it "promotes a member to admin" do
      patch "/api/v1/household_memberships/#{member_membership.id}", params: { role: "admin" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(member_membership.reload.role).to eq(Role::Admin)
    end

    it "refuses to demote the last admin" do
      admin_membership = household.household_memberships.find_by(user: admin)
      patch "/api/v1/household_memberships/#{admin_membership.id}", params: { role: "member" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(admin_membership.reload.role).to eq(Role::Admin)
    end

    it "forbids non-admin callers" do
      HouseholdMembership.where(user: admin, household: household).update_all(role: "member")
      patch "/api/v1/household_memberships/#{member_membership.id}", params: { role: "admin" }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/v1/household_memberships/:id" do
    it "lets an admin remove another member" do
      expect {
        delete "/api/v1/household_memberships/#{member_membership.id}", headers: headers
      }.to change { household.household_memberships.count }.by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "lets a member remove themselves (leave the household)" do
      member_token = create(:api_token, user: member_user, household: household, name: "M")
      delete "/api/v1/household_memberships/#{member_membership.id}",
        headers: { "Authorization" => "Bearer #{member_token.raw_token}" }
      expect(response).to have_http_status(:no_content)
    end

    it "refuses to remove the last admin" do
      member_membership.destroy! # leave admin as only member
      admin_membership = household.household_memberships.find_by(user: admin)
      delete "/api/v1/household_memberships/#{admin_membership.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
