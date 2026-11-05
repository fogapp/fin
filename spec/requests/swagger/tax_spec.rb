require "swagger_helper"

RSpec.describe "Tax", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }
  let(:year)          { Date.current.year }

  path "/api/v1/tax_profile" do
    get "The tax profile for a year" do
      tags "Tax"
      produces "application/json"
      description "An unsaved year returns defaults with `persisted: false` and a null id."
      parameter name: :year, in: :query, type: :integer, required: false, description: "Default: this year"

      response "200", "tax profile" do
        schema "$ref" => "#/components/schemas/TaxProfile"
        before { wealth }
        run_test!
      end
    end

    put "Create or update a year's tax profile" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          tax_year:                        { type: :integer },
          filing_status:                   { type: :string, enum: %w[single mfj] },
          state:                           { type: :string, description: "Two-letter state code" },
          projected_state_tax:             { type: :number, nullable: true },
          projected_wages:                 { type: :number },
          other_ordinary_income:           { type: :number },
          ltcg_qd_income:                  { type: :number },
          itemizing:                       { type: :boolean },
          salt_paid:                       { type: :number },
          itemized_other:                  { type: :number },
          prior_year_total_tax:            { type: :number, nullable: true },
          prior_year_agi:                  { type: :number, nullable: true },
          ytd_withholding_federal:         { type: :number },
          ytd_withholding_state:           { type: :number },
          amt_credit_carryforward_federal: { type: :number },
          amt_credit_carryforward_ca:      { type: :number }
        },
        required: %w[tax_year]
      }

      response "200", "profile saved" do
        schema "$ref" => "#/components/schemas/TaxProfile"
        let(:body) { { tax_year: year + 1, filing_status: "mfj", state: "CA", projected_wages: 420_000 } }
        run_test!
      end
    end
  end

  path "/api/v1/tax/report" do
    get "The year's tax picture: income, deductions, liability, payments, contributions, documents, flags" do
      tags "Tax"
      produces "application/json"
      parameter name: :year, in: :query, type: :integer, required: false, description: "Default: this year"

      response "200", "year report" do
        schema "$ref" => "#/components/schemas/TaxReport"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/tax/export" do
    get "The year report plus its supporting transactions, as one JSON bundle" do
      tags "Tax"
      produces "application/json"
      parameter name: :year, in: :query, type: :integer, required: false, description: "Default: this year"

      response "200", "export bundle" do
        schema "$ref" => "#/components/schemas/TaxExport"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/tax/estimated_payments" do
    post "Record an estimated tax payment" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          tax_year:     { type: :integer },
          jurisdiction: { type: :string, enum: %w[federal state] },
          paid_on:      { type: :string, format: :date },
          amount:       { type: :number },
          notes:        { type: :string }
        },
        required: %w[tax_year jurisdiction paid_on amount]
      }

      response "201", "payment recorded" do
        schema "$ref" => "#/components/schemas/TaxEstimatedPayment"
        let(:body) { { tax_year: year, jurisdiction: "federal", paid_on: "#{year}-06-15", amount: 4_000, notes: "Q2" } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { tax_year: year, jurisdiction: "federal" } }
        run_test!
      end
    end
  end

  path "/api/v1/tax/estimated_payments/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete an estimated tax payment" do
      tags "Tax"

      response "204", "payment deleted" do
        let(:id) { create(:estimated_tax_payment, tax_year: year).id }
        run_test!
      end
    end
  end

  path "/api/v1/tax/checklist_items" do
    post "Add a document to the year's checklist" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          tax_year:     { type: :integer },
          kind:         { type: :string, enum: %w[w2 1099_consolidated 1099_int 1099_r k1 1098 3921 3922 5498 property_tax charitable_receipt other] },
          source_label: { type: :string },
          status:       { type: :string, enum: %w[expected received corrected n_a] },
          reference_id: { type: :string, format: :uuid },
          notes:        { type: :string }
        },
        required: %w[tax_year kind source_label]
      }

      response "201", "item added" do
        schema "$ref" => "#/components/schemas/TaxChecklistItem"
        let(:body) { { tax_year: year, kind: "k1", source_label: "Fund LP", notes: "Usually late" } }
        run_test!
      end
    end
  end

  path "/api/v1/tax/checklist_items/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Mark a document received, corrected or not applicable" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          status: { type: :string, enum: %w[expected received corrected n_a] },
          notes:  { type: :string }
        }
      }

      response "200", "item updated" do
        schema "$ref" => "#/components/schemas/TaxChecklistItem"
        let(:id)   { create(:tax_checklist_item, tax_year: year).id }
        let(:body) { { status: "received" } }
        run_test!
      end
    end

    delete "Delete a manually added checklist item" do
      tags "Tax"

      response "204", "item deleted" do
        let(:id) { create(:tax_checklist_item, tax_year: year).id }
        run_test!
      end

      response "422", "auto-seeded items can only be marked n_a" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { create(:tax_checklist_item, :seeded, tax_year: year).id }
        run_test!
      end
    end
  end

  path "/api/v1/tax/adjustments" do
    post "Add an income, deduction, credit, payment or contribution adjustment" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          tax_year:     { type: :integer },
          kind:         { type: :string, enum: %w[income deduction credit payment contribution] },
          jurisdiction: { type: :string, enum: %w[federal state both] },
          label:        { type: :string },
          amount:       { type: :number },
          bucket:       { type: :string, enum: %w[401k ira hsa education], description: "Contribution adjustments only" },
          notes:        { type: :string }
        },
        required: %w[tax_year kind jurisdiction label amount]
      }

      response "201", "adjustment added" do
        schema "$ref" => "#/components/schemas/TaxAdjustment"
        let(:body) { { tax_year: year, kind: "contribution", jurisdiction: "federal", label: "Backdoor Roth", amount: 7_000, bucket: "ira" } }
        run_test!
      end
    end
  end

  path "/api/v1/tax/adjustments/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update an adjustment" do
      tags "Tax"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          label:  { type: :string },
          amount: { type: :number },
          notes:  { type: :string }
        }
      }

      response "200", "adjustment updated" do
        schema "$ref" => "#/components/schemas/TaxAdjustment"
        let(:id)   { create(:tax_adjustment, tax_year: year).id }
        let(:body) { { amount: 250, notes: "Corrected" } }
        run_test!
      end
    end

    delete "Delete an adjustment" do
      tags "Tax"

      response "204", "adjustment deleted" do
        let(:id) { create(:tax_adjustment, tax_year: year).id }
        run_test!
      end
    end
  end
end
