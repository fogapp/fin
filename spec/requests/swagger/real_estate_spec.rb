require "swagger_helper"

RSpec.describe "Real Estate", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/real_estate_properties" do
    get "List properties" do
      tags "Real Estate"
      produces "application/json"

      response "200", "properties listed" do
        schema "$ref" => "#/components/schemas/RealEstateIndex"
        before { wealth }
        run_test!
      end
    end

    post "Add a property" do
      tags "Real Estate"
      consumes "application/json"
      produces "application/json"
      description "When RentCast is configured, the address is resolved inline: the response already " \
                  "carries a value, cached facts, and history seeded from tax assessments and recorded " \
                  "sales. A lookup failure never fails the create — the property falls back to manual " \
                  "valuation with the reason in last_sync_error."
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:           { type: :string },
          address_line1:  { type: :string },
          address_line2:  { type: :string },
          city:           { type: :string },
          state:          { type: :string },
          zip_code:       { type: :string },
          purchase_price: { type: :number },
          purchase_date:  { type: :string, format: :date },
          value:          { type: :number, description: "Records a manual valuation; required in practice when RentCast isn't configured" },
          sync_enabled:   { type: :boolean },
          notes:          { type: :string }
        },
        required: %w[name address_line1]
      }

      response "201", "property created" do
        schema "$ref" => "#/components/schemas/RealEstateProperty"
        let(:body) { { name: "Primary residence", address_line1: "5500 Grand Lake Dr", value: 912_000 } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { {} }
        run_test!
      end
    end
  end

  path "/api/v1/real_estate_properties/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Get a property with its full valuation history" do
      tags "Real Estate"
      produces "application/json"

      response "200", "property returned" do
        schema "$ref" => "#/components/schemas/RealEstatePropertyDetail"
        let(:id) { wealth.property.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch "Update a property" do
      tags "Real Estate"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:         { type: :string },
          status:       { type: :string, enum: %w[owned sold] },
          sold_date:    { type: :string, format: :date },
          sold_price:   { type: :number },
          sync_enabled: { type: :boolean },
          value:        { type: :number },
          notes:        { type: :string }
        }
      }

      response "200", "property updated" do
        schema "$ref" => "#/components/schemas/RealEstateProperty"
        let(:id)   { wealth.property.id }
        let(:body) { { name: "Lake house" } }
        run_test!
      end
    end

    delete "Delete a property and its valuation history" do
      tags "Real Estate"

      response "204", "property deleted" do
        let(:id) { create(:real_estate_property).id }
        run_test!
      end
    end
  end

  path "/api/v1/real_estate_properties/{id}/refresh" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Refresh a property's value from RentCast now" do
      tags "Real Estate"
      produces "application/json"
      description "Spends from the monthly request allowance immediately rather than enqueueing."

      response "422", "RentCast not configured, or the monthly allowance is exhausted" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { create(:real_estate_property).id }
        run_test!
      end
    end
  end

  path "/api/v1/real_estate_properties/{id}/valuations" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Record a value by hand" do
      tags "Real Estate"
      consumes "application/json"
      produces "application/json"
      description "The newest as_of wins; on the same date a manual entry beats an automatic estimate."
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          amount: { type: :number },
          as_of:  { type: :string, format: :date, description: "Defaults to today" }
        },
        required: %w[amount]
      }

      response "201", "valuation recorded" do
        schema "$ref" => "#/components/schemas/RealEstateValuation"
        let(:id)   { create(:real_estate_property).id }
        let(:body) { { amount: 950_000 } }
        run_test!
      end
    end
  end

  path "/api/v1/real_estate_properties/{id}/valuations/{valuation_id}" do
    parameter name: :id,           in: :path, type: :string, format: :uuid, required: true
    parameter name: :valuation_id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete a recorded valuation" do
      tags "Real Estate"

      response "204", "valuation deleted" do
        let(:id)           { wealth.property.id }
        let(:valuation_id) { wealth.property.valuations.find_by!(source: "manual").id }
        run_test!
      end
    end
  end

  path "/api/v1/rentcast/configuration" do
    get "Get the RentCast integration state and this month's usage" do
      tags "Integrations"
      produces "application/json"

      response "200", "configuration returned" do
        schema "$ref" => "#/components/schemas/RentcastConfiguration"
        before { wealth }
        run_test!
      end
    end

    patch "Save RentCast credentials" do
      tags "Integrations"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          rentcast_configuration: {
            type: :object,
            properties: {
              api_key:               { type: :string },
              monthly_request_limit: { type: :integer, description: "The plan's allowance — 50 on the free tier" }
            }
          }
        }
      }

      response "200", "configuration saved" do
        schema "$ref" => "#/components/schemas/RentcastConfiguration"
        let(:body) { { rentcast_configuration: { api_key: "k", monthly_request_limit: 50 } } }
        run_test!
      end
    end

    delete "Remove the RentCast integration" do
      tags "Integrations"
      description "Properties and their recorded history stay; they simply stop updating automatically."

      response "204", "integration removed" do
        before { create(:rentcast_configuration) }
        run_test!
      end
    end
  end
end
