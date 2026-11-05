require "swagger_helper"

RSpec.describe "Accounts & Brokers", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  account_params = {
    name:             { type: :string },
    account_number:   { type: :string },
    account_type:     { type: :string, nullable: true },
    broker_id:        { type: :string, format: :uuid, nullable: true },
    balance:          { type: :number, nullable: true, description: "Recording a manual balance also writes a balance snapshot" },
    balance_currency: { type: :string },
    balance_usd:      { type: :number, nullable: true },
    hidden:           { type: :boolean },
    kind:             { type: :string, enum: %w[standard external] },
    tax_treatment:    { type: :string, enum: %w[taxable traditional_401k traditional_ira roth_401k roth_ira hsa education other] }
  }

  # ── Brokers ──────────────────────────────────────────────────────────────────

  path "/api/v1/brokers" do
    get "List brokers" do
      tags "Brokers"
      produces "application/json"

      response "200", "brokers listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Broker" }
        before { create(:account) }
        run_test! do |response|
          expect(response.parsed_body.first["account_count"]).to eq(1)
        end
      end
    end

    post "Create a broker" do
      tags "Brokers"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string } },
        required: %w[name]
      }

      response "201", "broker created" do
        schema "$ref" => "#/components/schemas/Broker"
        let(:body) { { name: "Vanguard" } }
        run_test!
      end
    end
  end

  path "/api/v1/brokers/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a broker with its accounts" do
      tags "Brokers"
      produces "application/json"

      response "200", "broker found" do
        schema "$ref" => "#/components/schemas/BrokerDetail"
        let(:id) { create(:account).broker_id }
        run_test! do |response|
          expect(response.parsed_body["accounts"]).to be_present
        end
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update a broker" do
      tags "Brokers"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string } },
        required: %w[name]
      }

      response "200", "broker updated" do
        schema "$ref" => "#/components/schemas/Broker"
        let(:id)   { create(:broker).id }
        let(:body) { { name: "Fidelity" } }
        run_test!
      end
    end

    delete "Delete a broker" do
      tags "Brokers"
      produces "application/json"

      response "204", "broker deleted" do
        let(:id) { create(:broker).id }
        run_test!
      end

      response "422", "broker still has accounts" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { create(:account).broker_id }
        run_test!
      end
    end
  end

  # ── Accounts ─────────────────────────────────────────────────────────────────

  path "/api/v1/accounts" do
    get "List accounts with ledger stats" do
      tags "Accounts"
      produces "application/json"

      response "200", "accounts listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/AccountWithStats" }
        before do
          account = create(:account, balance: 1234.5, balance_usd: 1234.5)
          create(:plaid_account, account: account)
          create(:cash_transaction, :bank, :debit, account: account)
          create(:loan, account: account)
        end
        run_test! do |response|
          expect(response.parsed_body.first).to include("linked_loan_id" => be_present, "plaid_item_id" => be_present)
        end
      end
    end

    post "Create an account" do
      tags "Accounts"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: account_params,
        required: %w[name account_number]
      }

      response "201", "account created" do
        schema "$ref" => "#/components/schemas/Account"
        let(:broker) { create(:broker) }
        let(:body)   { { name: "Checking", account_number: "****1234", account_type: "Checking", broker_id: broker.id } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { account_number: "****1234" } }
        run_test!
      end
    end
  end

  path "/api/v1/accounts/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch an account" do
      tags "Accounts"
      produces "application/json"

      response "200", "account found" do
        schema "$ref" => "#/components/schemas/Account"
        let(:id) { create(:account, balance: 10.0).id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update an account" do
      tags "Accounts"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: account_params }

      response "200", "account updated" do
        schema "$ref" => "#/components/schemas/Account"
        let(:id)   { create(:account).id }
        let(:body) { { name: "Main Checking", balance: 2500.0, tax_treatment: "roth_ira" } }
        run_test!
      end
    end
  end
end
