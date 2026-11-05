require "swagger_helper"

RSpec.describe "Stats", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/stats" do
    get "Every tracked stat with its latest value, change and sparkline" do
      tags "Stats"
      produces "application/json"

      response "200", "stats index" do
        schema "$ref" => "#/components/schemas/StatsIndexData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/stats/{key}" do
    parameter name: :key, in: :path, schema: { type: :string, pattern: "^[a-z0-9_]+$" }, required: true,
              description: "Stat key, e.g. monthly_spend"

    get "One stat's series, summary, breakdown and drill-down" do
      tags "Stats"
      produces "application/json"
      parameter name: :from, in: :query, type: :string, required: false, description: "ISO start date"
      parameter name: :to,   in: :query, type: :string, required: false, description: "ISO end date"

      response "200", "stat detail" do
        schema "$ref" => "#/components/schemas/StatDetailData"
        let(:key) { "monthly_spend" }
        before { wealth }
        run_test!
      end

      response "404", "unknown stat" do
        schema "$ref" => "#/components/schemas/Error"
        let(:key) { "no_such_stat" }
        run_test!
      end
    end
  end
end
