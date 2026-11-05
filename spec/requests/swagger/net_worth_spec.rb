require "swagger_helper"

RSpec.describe "Net Worth", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/net_worth" do
    get "Net worth timeline" do
      tags "Net Worth"
      produces "application/json"
      description "Household net worth over time, reconstructed from account balance snapshots, " \
                  "position-based portfolio history, loan payment replay, real estate valuations, " \
                  "and equity compensation. Credit and loans are negative so liabilities stack below zero."
      parameter name: :range, in: :query, schema: { type: :string, enum: %w[3m ytd 1y all] }, required: false,
                description: "Named window for the series and breakdown (default 1y); ignored when from is given"
      parameter name: :from, in: :query, type: :string, required: false,
                description: "ISO start date of an explicit window (takes precedence over range)"
      parameter name: :to, in: :query, type: :string, required: false,
                description: "ISO end date of an explicit window (default and maximum: today)"

      response "200", "net worth data" do
        schema "$ref" => "#/components/schemas/NetWorthData"
        before { wealth }
        run_test!
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/net_worth/projection" do
    get "Project net worth forward" do
      tags "Net Worth"
      produces "application/json"
      parameter name: :years,   in: :query, type: :integer, required: false, description: "Horizon in years (1–40, default 10)"
      parameter name: :growth,  in: :query, type: :number,  required: false, description: "Annual growth rate as a percentage (-20–30)"
      parameter name: :monthly, in: :query, type: :number,  required: false,
                description: "Monthly contribution (default: the recent average monthly net cashflow)"

      response "200", "projection" do
        schema "$ref" => "#/components/schemas/NetWorthProjectionData"
        let(:years) { 5 }
        before { wealth }
        run_test!
      end
    end
  end
end
