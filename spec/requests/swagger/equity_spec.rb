require "swagger_helper"

RSpec.describe "Equity", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/equity/summary" do
    get "Equity compensation: companies, grants, vesting and totals" do
      tags "Equity"
      produces "application/json"

      response "200", "equity summary" do
        schema "$ref" => "#/components/schemas/EquitySummary"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/equity/companies" do
    post "Add a company" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:            { type: :string },
          public_company:  { type: :boolean },
          ticker:          { type: :string, description: "Links a public company to its market security" },
          c_corp:          { type: :boolean },
          qsbs_candidate:  { type: :boolean },
          preferred_price: { type: :number },
          notes:           { type: :string },
          initial_fmv: {
            type: :object,
            properties: {
              price_per_share: { type: :number },
              effective_date:  { type: :string, format: :date },
              source:          { type: :string, enum: %w[409a round tender market manual] }
            }
          }
        },
        required: %w[name]
      }

      response "201", "company created" do
        schema "$ref" => "#/components/schemas/EquityCompany"
        let(:body) do
          { name: "Widgets Inc", c_corp: true, preferred_price: 8,
            initial_fmv: { price_per_share: 3.5, effective_date: Date.current.to_s, source: "409a" } }
        end
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { name: "" } }
        run_test!
      end
    end
  end

  path "/api/v1/equity/companies/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update a company" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:            { type: :string },
          preferred_price: { type: :number },
          qsbs_candidate:  { type: :boolean },
          notes:           { type: :string }
        }
      }

      response "200", "company updated" do
        schema "$ref" => "#/components/schemas/EquityCompany"
        let(:id)   { wealth.company.id }
        let(:body) { { notes: "Series D closed" } }
        run_test!
      end
    end

    delete "Delete a company with its grants and FMV history" do
      tags "Equity"

      response "204", "company deleted" do
        let(:id) { create(:equity_company).id }
        run_test!
      end
    end
  end

  path "/api/v1/equity/companies/{id}/fmv_entries" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Record a fair-market value" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          price_per_share: { type: :number },
          effective_date:  { type: :string, format: :date },
          source:          { type: :string, enum: %w[409a round tender market manual] }
        },
        required: %w[price_per_share effective_date source]
      }

      response "201", "value recorded" do
        schema "$ref" => "#/components/schemas/EquityFmvEntry"
        let(:id)   { wealth.company.id }
        let(:body) { { price_per_share: 13.25, effective_date: Date.current.to_s, source: "409a" } }
        run_test!
      end
    end
  end

  path "/api/v1/equity/fmv_entries/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete a fair-market value entry" do
      tags "Equity"

      response "204", "entry deleted" do
        let(:id) { create(:equity_fmv_entry).id }
        run_test!
      end
    end
  end

  path "/api/v1/equity/grants" do
    post "Add a grant" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          equity_company_id:         { type: :string, format: :uuid },
          label:                     { type: :string },
          grant_type:                { type: :string, enum: %w[iso nso rsu rsa] },
          grant_date:                { type: :string, format: :date },
          vesting_commencement_date: { type: :string, format: :date },
          quantity:                  { type: :number },
          strike_price:              { type: :number },
          early_exercisable:         { type: :boolean },
          double_trigger:            { type: :boolean },
          expiration_date:           { type: :string, format: :date },
          pte_window_days:           { type: :integer },
          vesting_interval:          { type: :string, enum: %w[monthly quarterly annual] },
          vesting_occurrences:       { type: :integer },
          cliff_installments:        { type: :integer },
          notes:                     { type: :string },
          custom_tranches: {
            type: :array,
            items: {
              type: :object,
              properties: { date: { type: :string, format: :date }, quantity: { type: :number } },
              required: %w[date quantity]
            },
            description: "Overrides the interval schedule; an empty array clears it"
          }
        },
        required: %w[equity_company_id grant_type grant_date quantity]
      }

      response "201", "grant created" do
        schema "$ref" => "#/components/schemas/EquityGrant"
        let(:body) do
          { equity_company_id: wealth.company.id, label: "Refresh", grant_type: "nso", grant_date: Date.current.to_s,
            quantity: 1_200, strike_price: 12, vesting_interval: "quarterly", vesting_occurrences: 16, cliff_installments: 4 }
        end
        run_test!
      end
    end
  end

  path "/api/v1/equity/grants/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update a grant" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          label:           { type: :string },
          expiration_date: { type: :string, format: :date },
          notes:           { type: :string }
        }
      }

      response "200", "grant updated" do
        schema "$ref" => "#/components/schemas/EquityGrant"
        let(:id)   { wealth.iso_grant.id }
        let(:body) { { notes: "Board approved" } }
        run_test!
      end
    end

    delete "Delete a grant and its events" do
      tags "Equity"

      response "204", "grant deleted" do
        let(:id) { create(:equity_grant).id }
        run_test!
      end
    end
  end

  path "/api/v1/equity/grants/{id}/events" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Record an exercise, settlement, sale or cancellation" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          kind:              { type: :string, enum: %w[exercise settlement sale cancellation] },
          occurred_on:       { type: :string, format: :date },
          quantity:          { type: :number },
          share_price:       { type: :number },
          method:            { type: :string, enum: %w[cash cashless sell_to_cover net_settlement] },
          buyer_type:        { type: :string, enum: %w[company_tender third_party] },
          election_83b:      { type: :boolean },
          election_83b_date: { type: :string, format: :date },
          shares_withheld:   { type: :number },
          notes:             { type: :string }
        },
        required: %w[kind occurred_on quantity]
      }

      response "201", "event recorded" do
        schema "$ref" => "#/components/schemas/EquityGrantEvent"
        let(:id)   { wealth.iso_grant.id }
        let(:body) { { kind: "exercise", occurred_on: Date.current.to_s, quantity: 200, share_price: 12, method: "cash" } }
        run_test!
      end
    end
  end

  path "/api/v1/equity/events/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete a grant event" do
      tags "Equity"

      response "204", "event deleted" do
        let(:id) { wealth.exercise.id }
        run_test!
      end
    end
  end

  path "/api/v1/equity/grants/{id}/exercise_plan" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Plan an option exercise against the year's AMT headroom" do
      tags "Equity"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          quantity:        { type: :number, description: "Shares to exercise (default: the AMT crossover, capped at exercisable)" },
          tax_year:        { type: :integer },
          stress_drop_pct: { type: :integer, description: "Share-price drop to stress-test the plan against" }
        }
      }

      response "200", "exercise plan" do
        schema "$ref" => "#/components/schemas/ExercisePlan"
        let(:id)   { wealth.iso_grant.id }
        let(:body) { { tax_year: Date.current.year } }
        run_test!
      end

      response "422", "not an option grant, no share value, or tax profile incomplete" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id)   { wealth.rsu_grant.id }
        let(:body) { {} }
        run_test!
      end
    end
  end
end
