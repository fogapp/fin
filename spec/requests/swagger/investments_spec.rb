require "swagger_helper"

RSpec.describe "Investments & Analytics", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── Position Snapshots ────────────────────────────────────────────────────────

  # ── Cost Basis ────────────────────────────────────────────────────────────────

  path "/api/v1/cost_basis" do
    get "Cost basis summary across all positions" do
      tags "Analytics"
      produces "application/json"

      response "200", "cost basis data returned" do
        schema type: :object, properties: {
          summary: {
            type: :object,
            properties: {
              total_positions:  { type: :integer },
              complete:         { type: :integer },
              partial:          { type: :integer },
              unknown:          { type: :integer },
              total_value:      { type: :number },
              known_cost_basis: { type: :number }
            }
          },
          positions: { type: :array, items: { type: :object } }
        }, required: %w[summary positions]
        run_test!
      end
    end
  end

  # ── Benchmarks ────────────────────────────────────────────────────────────────

  path "/api/v1/benchmarks" do
    get "List available benchmark indices" do
      tags "Analytics"
      produces "application/json"

      response "200", "benchmarks listed" do
        schema type: :array, items: {
          type: :object,
          properties: {
            symbol: { type: :string },
            label:  { type: :string }
          },
          required: %w[symbol label]
        }
        run_test!
      end
    end
  end

  path "/api/v1/benchmarks/{symbol}" do
    parameter name: :symbol, in: :path, type: :string, required: true, description: "Ticker symbol (e.g. SPY)"

    get "Price history for a benchmark ticker" do
      tags "Analytics"
      produces "application/json"

      response "200", "benchmark price history" do
        schema type: :object, properties: {
          symbol:  { type: :string },
          label:   { type: :string },
          prices:  { type: :array, items: { type: :array, description: "[date_string, close_price]" } },
          syncing: { type: :boolean }
        }, required: %w[symbol label prices syncing]
        let(:symbol) { "SPY" }
        run_test!
      end
    end
  end

  # ── Cashflow Activity ─────────────────────────────────────────────────────────

  path "/api/v1/cashflow/activity" do
    get "Transaction activity feed for the cashflow view" do
      tags "Cashflow"
      produces "application/json"
      parameter name: :start_date, in: :query, schema: { type: :string, format: :date }, required: false
      parameter name: :end_date,   in: :query, schema: { type: :string, format: :date }, required: false

      response "200", "activity data returned" do
        schema type: :object, properties: {
          days: {
            type: :array,
            items: {
              type: :object,
              properties: {
                date:   { type: :string, format: :date },
                spend:  { type: :number },
                income: { type: :number }
              },
              required: %w[date spend income]
            }
          },
          total_spend:  { type: :number },
          total_income: { type: :number },
          net:          { type: :number }
        }, required: %w[days total_spend total_income net]
        run_test!
      end
    end
  end

  # ── Crypto ────────────────────────────────────────────────────────────────────

  path "/api/v1/crypto" do
    get "Crypto holdings summary" do
      tags "Crypto"
      produces "application/json"
      parameter name: :from, in: :query, type: :string, required: false,
                description: "ISO start date: scopes activity charts, top assets, by-account, and recent " \
                             "transactions (summary and positions are point-in-time)"
      parameter name: :to, in: :query, type: :string, required: false, description: "ISO end date (inclusive)"

      response "200", "crypto data returned" do
        schema type: :object, properties: {
          summary:             { type: :object },
          positions:           { type: :array, items: { type: :object } },
          balance_history:     { type: :object, additionalProperties: { type: :number } },
          monthly_volume:      { type: :array, items: { type: :array } },
          cumulative_invested: { type: :array, items: { type: :array } },
          top_assets:          { type: :array, items: { type: :object } },
          by_account:          { type: :object, additionalProperties: { type: :number } },
          recent:              { type: :array, items: { type: :object } }
        }, required: %w[summary positions]
        run_test!
      end
    end
  end
end
