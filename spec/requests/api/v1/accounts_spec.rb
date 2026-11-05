require "rails_helper"

RSpec.describe "Api::V1::Accounts", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/accounts" do
    it "returns 401 without authentication" do
      get "/api/v1/accounts"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns accounts with transaction counts and portfolio value" do
      create(:account)

      get "/api/v1/accounts", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first).to include(
        "name", "broker_name", "cash_transaction_count",
        "investment_transaction_count", "portfolio_value", "latest_transaction_date"
      )
    end

    it "counts both ledgers and reports the latest date across them" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, transaction_date: Date.new(2026, 3, 1))
      create(:cash_transaction, :bank, account: account, transaction_date: Date.new(2026, 3, 9))
      create(:investment_transaction, account: account, trade_date: Date.new(2026, 4, 2))

      get "/api/v1/accounts", headers: auth_headers

      row = response.parsed_body.find { |a| a["id"] == account.id }
      expect(row).to include(
        "cash_transaction_count" => 2,
        "investment_transaction_count" => 1,
        "latest_transaction_date" => "2026-04-02"
      )
    end
  end

  describe "GET /api/v1/accounts/:id" do
    it "returns the account" do
      account = create(:account)

      get "/api/v1/accounts/#{account.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(account.id)
      expect(response.parsed_body["broker_name"]).to eq(account.broker.name)
    end

    it "returns 404 for a nonexistent account" do
      get "/api/v1/accounts/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/accounts" do
    it "creates and returns the account" do
      broker = create(:broker)
      post "/api/v1/accounts",
           params: { name: "Checking", account_number: "1234", account_type: "Checking", broker_id: broker.id },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Checking")
      expect(response.parsed_body["broker_name"]).to eq(broker.name)
    end

    it "returns 422 when invalid" do
      post "/api/v1/accounts", params: { name: "" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates an external account from just a name" do
      post "/api/v1/accounts",
           params: { name: "Schwab", kind: "external" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("Schwab")
      expect(body["kind"]).to eq("external")
      expect(body["broker_id"]).to be_nil
      expect(body["broker_name"]).to be_nil
      expect(body["account_number"]).to start_with("ext-")
    end

    it "rejects a broker-less standard account" do
      post "/api/v1/accounts",
           params: { name: "Checking", account_number: "1234" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "serializes kind on index" do
      create(:account)
      get "/api/v1/accounts", headers: auth_headers
      expect(response.parsed_body.first["kind"]).to eq("standard")
    end
  end

  describe "PATCH /api/v1/accounts/:id" do
    it "updates and returns the account" do
      account = create(:account, name: "Old Name")
      patch "/api/v1/accounts/#{account.id}",
            params: { name: "New Name" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
    end

    it "returns 404 for a nonexistent account" do
      patch "/api/v1/accounts/0", params: { name: "x" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "updates and serializes tax_treatment" do
      account = create(:account)
      expect(account.tax_treatment).to eq(Account::TaxTreatment::Taxable)

      patch "/api/v1/accounts/#{account.id}",
            params: { tax_treatment: "traditional_401k" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tax_treatment"]).to eq("traditional_401k")
      expect(account.reload.tax_treatment).to eq(Account::TaxTreatment::Traditional401k)
    end

    it "rejects unknown tax treatments" do
      account = create(:account)
      patch "/api/v1/accounts/#{account.id}",
            params: { tax_treatment: "offshore" },
            headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
