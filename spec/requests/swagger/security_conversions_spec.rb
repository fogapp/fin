require "swagger_helper"

RSpec.describe "Security conversions", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:smney)         { create(:security, ticker: "SMNEY", name: "Siemens Energy Ag-Unsp") }
  let(:smery)         { create(:security, ticker: "SMERY", name: "Siemens Energy AG - ADR - Sponsored") }
  let(:conversion) do
    SecurityConversion.create!(
      from_security: smney, to_security: smery, effective_date: Date.new(2026, 1, 30), ratio: 5,
      evidence: { "account_name" => "Global", "raw_ratio" => 5.0, "shared_name_words" => %w[energy siemens] }
    )
  end

  path "/api/v1/security_conversions" do
    get "List security conversions" do
      tags "Instruments"
      produces "application/json"
      parameter name: :status, in: :query, required: false,
                schema: { "$ref" => "#/components/schemas/SecurityConversionStatus" }
      parameter name: :security_id, in: :query, required: false, schema: { type: :string, format: :uuid },
                description: "Only conversions from or to this security"

      response "200", "conversions" do
        schema type: :array, items: { "$ref" => "#/components/schemas/SecurityConversion" }
        before { conversion }
        run_test! do |response|
          expect(response.parsed_body.size).to eq(1)
        end
      end
    end

    post "Record a conversion by hand (starts confirmed)" do
      tags "Instruments"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          from_security_id: { type: :string, format: :uuid },
          to_security_id:   { type: :string, format: :uuid },
          effective_date:   { type: :string, format: :date },
          ratio:            { type: :number, format: :float }
        },
        required: %w[from_security_id to_security_id effective_date ratio]
      }

      response "201", "recorded" do
        schema "$ref" => "#/components/schemas/SecurityConversion"
        let(:body) { { from_security_id: smney.id, to_security_id: smery.id, effective_date: "2026-01-30", ratio: 5 } }
        run_test! do |response|
          expect(response.parsed_body["status"]).to eq("confirmed")
        end
      end

      response "422", "invalid" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { from_security_id: smney.id, to_security_id: smney.id, effective_date: "2026-01-30", ratio: 1 } }
        run_test!
      end
    end
  end

  path "/api/v1/security_conversions/{id}/confirm" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Confirm a suggested conversion" do
      tags "Instruments"
      produces "application/json"

      response "200", "confirmed" do
        schema "$ref" => "#/components/schemas/SecurityConversion"
        let(:id) { conversion.id }
        run_test! do |response|
          expect(response.parsed_body["status"]).to eq("confirmed")
        end
      end
    end
  end

  path "/api/v1/security_conversions/{id}/dismiss" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Dismiss a suggested conversion (never suggested again)" do
      tags "Instruments"
      produces "application/json"

      response "200", "dismissed" do
        schema "$ref" => "#/components/schemas/SecurityConversion"
        let(:id) { conversion.id }
        run_test! do |response|
          expect(response.parsed_body["status"]).to eq("dismissed")
        end
      end
    end
  end

  path "/api/v1/security_conversions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete a conversion" do
      tags "Instruments"

      response "204", "deleted" do
        let(:id) { conversion.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end
end
