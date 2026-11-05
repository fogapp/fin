require "swagger_helper"

RSpec.describe "Portfolio & Investments", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  def self.window_parameters(paged: false)
    parameter name: :from, in: :query, type: :string, required: false,
              description: "ISO start date: scopes charts, top securities, by-account and transactions " \
                           "(and the period stats, which otherwise cover the trailing 12 months)"
    parameter name: :to, in: :query, type: :string, required: false, description: "ISO end date (inclusive)"
    return unless paged

    parameter name: :limit,  in: :query, type: :string, required: false, description: "Transactions to return, or `all`"
    parameter name: :offset, in: :query, type: :integer, required: false
  end

  path "/api/v1/dashboard" do
    get "Dashboard summary" do
      tags "Dashboard"
      produces "application/json"
      parameter name: :broker_id, in: :query, schema: { type: :string, format: :uuid }, required: false,
                description: "Scope all data to a specific broker's accounts"

      response "200", "dashboard data" do
        schema "$ref" => "#/components/schemas/DashboardData"
        before { wealth }
        run_test!
      end

      response "404", "broker not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:broker_id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  path "/api/v1/portfolio" do
    get "Portfolio overview: positions, allocation and value history" do
      tags "Portfolio"
      produces "application/json"

      response "200", "portfolio data" do
        schema "$ref" => "#/components/schemas/PortfolioData"
        before { wealth }
        run_test!
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end
  end

  path "/api/v1/portfolio/performance" do
    get "Portfolio returns against benchmarks" do
      tags "Portfolio"
      produces "application/json"
      parameter name: :from, in: :query, type: :string, required: false, description: "ISO start date (default: a year ago)"
      parameter name: :to,   in: :query, type: :string, required: false, description: "ISO end date (default: today)"

      response "200", "performance data" do
        schema "$ref" => "#/components/schemas/PortfolioPerformanceData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/cost_basis" do
    get "Cost-basis coverage per position" do
      tags "Portfolio"
      produces "application/json"
      description "Each position's basis resolved from manual lots (when they cover the holding), the " \
                  "snapshot's reported basis, or the ledger average — with the source and coverage."

      response "200", "cost basis positions" do
        schema "$ref" => "#/components/schemas/CostBasisData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/crypto" do
    get "Crypto holdings and activity" do
      tags "Investments"
      produces "application/json"
      window_parameters

      response "200", "crypto data" do
        schema "$ref" => "#/components/schemas/CryptoData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/buys" do
    get "Buys summary" do
      tags "Investments"
      produces "application/json"
      window_parameters

      response "200", "buys data" do
        schema "$ref" => "#/components/schemas/BuysData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/sells" do
    get "Sells and realized gains" do
      tags "Investments"
      produces "application/json"
      window_parameters(paged: true)

      response "200", "sells data" do
        schema "$ref" => "#/components/schemas/SellsData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/dividends" do
    get "Dividend income" do
      tags "Investments"
      produces "application/json"
      window_parameters(paged: true)

      response "200", "dividends data" do
        schema "$ref" => "#/components/schemas/DividendsData"
        before { wealth }
        run_test!
      end
    end
  end
end
