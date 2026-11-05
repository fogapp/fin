require "swagger_helper"

RSpec.describe "Merchants", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  merchant_params = {
    name:        { type: :string },
    category_id: { type: :string, format: :uuid, nullable: true },
    notes:       { type: :string, nullable: true }
  }

  path "/api/v1/merchants" do
    get "List merchants" do
      tags "Merchants"
      produces "application/json"

      response "200", "merchants listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/MerchantWithStats" }
        before { rich_cash_transaction }
        run_test! do |response|
          expect(response.parsed_body.first["transaction_count"]).to eq(1)
        end
      end
    end

    post "Create (or update by name) a merchant" do
      tags "Merchants"
      description "Idempotent on name: an existing merchant with this name is updated and returned with 200."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: merchant_params, required: %w[name] }

      response "201", "merchant created" do
        schema "$ref" => "#/components/schemas/Merchant"
        let(:body) { { name: "Starbucks", category_id: create(:category).id, notes: "Coffee" } }
        run_test!
      end

      response "200", "existing merchant updated" do
        schema "$ref" => "#/components/schemas/Merchant"
        before     { create(:merchant, name: "Starbucks") }
        let(:body) { { name: "Starbucks", notes: "Coffee" } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { name: "" } }
        run_test!
      end
    end
  end

  path "/api/v1/merchants/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a merchant with monthly activity" do
      tags "Merchants"
      produces "application/json"

      response "200", "merchant found" do
        schema "$ref" => "#/components/schemas/MerchantDetail"
        let(:merchant) { create(:merchant, notes: "Weekly shop") }
        let(:id) { merchant.id }
        before do
          create(:cash_transaction, :bank, :debit, merchant: merchant)
          create(:cash_transaction, :bank, :credit, merchant: merchant)
        end
        run_test! do |response|
          expect(response.parsed_body).to include("monthly_spend" => be_present, "monthly_income" => be_present)
        end
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update a merchant" do
      tags "Merchants"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: merchant_params }

      response "200", "merchant updated" do
        schema "$ref" => "#/components/schemas/Merchant"
        let(:id)   { create(:merchant).id }
        let(:body) { { name: "Updated Name" } }
        run_test!
      end
    end

    delete "Delete a merchant" do
      tags "Merchants"

      response "204", "merchant deleted" do
        let(:id) { create(:merchant).id }
        run_test!
      end
    end
  end

  path "/api/v1/merchants/{id}/exclude" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Exclude a merchant from spend totals" do
      tags "Merchants"

      response "204", "merchant excluded" do
        let(:id) { create(:merchant).id }
        run_test!
      end
    end
  end

  path "/api/v1/merchants/{id}/include" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Count a previously excluded merchant in spend again" do
      tags "Merchants"

      response "204", "merchant included" do
        let(:id) { create(:merchant, excluded: true).id }
        run_test!
      end
    end
  end
end
