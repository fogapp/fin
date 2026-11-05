require "rails_helper"

RSpec.describe "Households", type: :request do
  let(:user)      { Current.user }
  let(:household) { Current.household }
  let(:token)     { create(:api_token, user: user, household: household, name: "T") }
  let(:headers)   { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/households" do
    it "returns every household the user belongs to, marking the active one" do
      other = create(:household, name: "Other")
      create(:household_membership, user: user, household: other, role: "member")

      get "/api/v1/households", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.size).to eq(2)
      active = body.find { |h| h["active"] }
      expect(active["id"]).to eq(household.id)
      expect(active["role"]).to eq("admin")
    end
  end

  describe "POST /api/v1/households" do
    it "creates a new household and makes the caller admin" do
      expect {
        post "/api/v1/households", params: { name: "Side Hustle" }, headers: headers
      }.to change(Household, :count).by(1)
       .and change { user.household_memberships.count }.by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["role"]).to eq("admin")
    end
  end

  describe "PATCH /api/v1/households/:id" do
    it "renames the active household when called by an admin" do
      patch "/api/v1/households/#{household.id}", params: { name: "Renamed" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(household.reload.name).to eq("Renamed")
    end

    it "forbids non-admins" do
      HouseholdMembership.where(user: user, household: household).update_all(role: "member")
      patch "/api/v1/households/#{household.id}", params: { name: "Nope" }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects renaming a non-active household via this token" do
      other = create(:household, name: "Other")
      patch "/api/v1/households/#{other.id}", params: { name: "X" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "updates the workflow log level" do
      patch "/api/v1/households/#{household.id}",
            params: { workflow_log_level: "debug" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["workflow_log_level"]).to eq("debug")
      expect(household.reload.workflow_log_level).to eq(Workflows::LogLevel::Debug)
    end

    it "toggles counting unvested equity toward net worth" do
      patch "/api/v1/households/#{household.id}",
            params: { include_unvested_equity: true }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["include_unvested_equity"]).to be(true)
      expect(household.reload.include_unvested_equity).to be(true)

      patch "/api/v1/households/#{household.id}",
            params: { include_unvested_equity: false }, headers: headers
      expect(household.reload.include_unvested_equity).to be(false)
    end

    it "rejects unknown workflow log levels" do
      patch "/api/v1/households/#{household.id}",
            params: { workflow_log_level: "verbose" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(household.reload.workflow_log_level).to eq(Workflows::LogLevel::Info)
    end
  end

  describe "DELETE /api/v1/households/:id" do
    let!(:other) do
      h = create(:household, name: "Other")
      create(:household_membership, user: user, household: h, role: "admin")
      h
    end

    it "deletes the household, cascades scoped data, and issues a token for the next household" do
      Current.set(household: household) { create(:broker, name: "BankToBeDeleted") }
      headers # eager-eval the let-created token before the change block

      expect {
        delete "/api/v1/households/#{household.id}", headers: headers
      }.to change(Household, :count).by(-1)
       .and change(Broker, :count).by(-1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body.dig("household", "id")).to eq(other.id)
    end

    it "mints the replacement token as a session token so it stays out of the PAT list" do
      delete "/api/v1/households/#{household.id}", headers: headers

      expect(response).to have_http_status(:ok)
      replacement = ApiToken.unscoped.order(created_at: :desc).first
      expect(replacement.session).to be true
      expect(replacement.household_id).to eq(other.id)
    end

    it "deletes a household with balance snapshots, loans, and tagged transactions (full cascade)" do
      # Regression: account_balance_snapshots→accounts, loans→households and
      # cash_transaction_tags→cash_transactions/tags had NO ACTION FKs, so the
      # delete 500'd with PG::ForeignKeyViolation once real data existed.
      account = create(:account)
      AccountBalanceSnapshot.record(account, source: AccountBalanceSnapshot::Source::Manual, balance: 100, balance_usd: 100)
      create(:loan, account: account)
      txn = create(:cash_transaction, :bank, account: account, amount: -5)
      txn.tags << create(:tag)
      headers # eager-eval the let-created token before the change block

      expect {
        delete "/api/v1/households/#{household.id}", headers: headers
      }.to change(Household, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(AccountBalanceSnapshot.count).to eq(0)
      expect(Loan.unscoped.count).to eq(0)
      expect(CashTransactionTag.count).to eq(0)
    end

    it "forbids non-admins" do
      HouseholdMembership.where(user: user, household: household).update_all(role: "member")
      delete "/api/v1/households/#{household.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to delete the caller's only household" do
      other.destroy! # leave user with only the active household
      delete "/api/v1/households/#{household.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(Household.exists?(household.id)).to be true
    end

    it "404s when the user is not a member" do
      stranger = create(:household, name: "Stranger")
      delete "/api/v1/households/#{stranger.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
