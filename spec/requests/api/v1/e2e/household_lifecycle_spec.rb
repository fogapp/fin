require "rails_helper"

# E2E flow: an admin invites another user, who joins, switches into the
# inviting household, and sees that household's data without leaking
# into their own. Covers the invite create/show/revoke chain and — most
# importantly — that HouseholdScoped models actually scope to
# Current.household after switch_household.
RSpec.describe "E2E: household lifecycle / multi-tenant isolation", type: :request do
  # Default household + admin user set up by the household_context support file.
  let(:household_a)   { Current.household }
  let(:admin_token)   { create(:api_token) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.raw_token}" } }
  let(:account_a)     { create(:account, name: "A's checking") }

  describe "invite create → public lookup → revoke" do
    it "creates an invite, exposes it without auth, and lets the admin revoke it" do
      post "/api/v1/invites",
           params: { role: "member", expires_in_days: 14 },
           headers: admin_headers, as: :json
      expect(response).to have_http_status(:created)
      code = response.parsed_body["code"]
      expect(code).to be_present
      expect(response.parsed_body["role"]).to eq("member")

      # Public lookup — no auth header on purpose
      get "/api/v1/invites/#{code}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["household"]["id"]).to eq(household_a.id)

      get "/api/v1/invites", headers: admin_headers
      expect(response.parsed_body.map { |i| i["code"] }).to include(code)

      delete "/api/v1/invites/#{code}", headers: admin_headers
      expect(response).to have_http_status(:no_content)

      get "/api/v1/invites/#{code}"
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to let a non-admin create or list invites" do
      non_admin_user = User.create!(email: "member@example.com", name: "Member")
      HouseholdMembership.create!(user: non_admin_user, household: household_a, role: "member")
      member_token = create(:api_token, user: non_admin_user, household: household_a)
      member_headers = { "Authorization" => "Bearer #{member_token.raw_token}" }

      post "/api/v1/invites", params: { role: "member" }, headers: member_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/invites", headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "switch_household + multi-tenant isolation" do
    let!(:household_b) { Household.create!(name: "B House") }
    let(:user_b)       { User.create!(email: "userb@example.com", name: "User B") }
    let!(:membership_a) { HouseholdMembership.create!(user: user_b, household: household_a, role: "member") }
    let!(:membership_b) { HouseholdMembership.create!(user: user_b, household: household_b, role: "admin") }
    let(:user_b_token_in_a) { create(:api_token, user: user_b, household: household_a) }
    let(:user_b_headers)    { { "Authorization" => "Bearer #{user_b_token_in_a.raw_token}" } }

    before do
      # Data in household A (already the Current household)
      create(:cash_transaction, :bank, account: account_a, description: "A-only txn")

      # Data in household B
      Current.set(household: household_b) do
        b_account = create(:account, name: "B's checking")
        create(:cash_transaction, :bank, account: b_account, description: "B-only txn")
      end
    end

    it "switches household and returns a token scoped to the new household" do
      post "/api/v1/auth/switch_household",
           params: { household_id: household_b.id },
           headers: user_b_headers, as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["household"]["id"]).to   eq(household_b.id)
      expect(body["household"]["role"]).to eq("admin")

      new_headers = { "Authorization" => "Bearer #{body['token']}" }

      # /me reflects the switched household
      get "/api/v1/me", headers: new_headers
      expect(response.parsed_body["household"]["id"]).to eq(household_b.id)

      # /cash_transactions now only returns B's data
      get "/api/v1/cash_transactions", headers: new_headers
      descriptions = response.parsed_body.map { |t| t["description"] }
      expect(descriptions).to     include("B-only txn")
      expect(descriptions).not_to include("A-only txn")
    end

    it "refuses to switch into a household the user is not a member of" do
      stranger_household = Household.create!(name: "Stranger")

      post "/api/v1/auth/switch_household",
           params: { household_id: stranger_household.id },
           headers: user_b_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "scopes /accounts and /cash_transactions to the active household by default" do
      # Without switching, user B's token is bound to household A → sees A's data only
      get "/api/v1/cash_transactions", headers: user_b_headers
      descriptions = response.parsed_body.map { |t| t["description"] }
      expect(descriptions).to     include("A-only txn")
      expect(descriptions).not_to include("B-only txn")
    end
  end
end
