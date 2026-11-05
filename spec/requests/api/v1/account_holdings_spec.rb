require "rails_helper"

RSpec.describe "Api::V1::Accounts holdings", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:household)    { token.household }
  let(:account)      { create(:account, household: household) }

  def holding(ticker:, market_value:)
    security = create(:security, ticker: ticker, name: "#{ticker} Inc")
    create(:position_snapshot,
           household:    household,
           account:      account,
           security:     security,
           as_of_date:   Date.current,
           market_value: market_value,
           cost_basis:   market_value / 2,
           quantity:     10)
  end

  describe "GET /api/v1/accounts/:id/holdings" do
    it "returns 401 without authentication" do
      get "/api/v1/accounts/#{account.id}/holdings"
      expect(response).to have_http_status(:unauthorized)
    end

    it "serializes each position with its security's identifiers" do
      holding(ticker: "AAA", market_value: 100)

      get "/api/v1/accounts/#{account.id}/holdings", headers: auth_headers

      expect(response).to have_http_status(:ok)
      row = response.parsed_body["positions"].first
      expect(row["security_ticker"]).to eq("AAA")
      expect(row["security_name"]).to eq("AAA Inc")
    end

    # The serializer reads ticker/name/cusip off every row's security. The
    # relation used to `joins(:security)` without `includes`, which preloads
    # nothing — so the query count grew with the number of holdings.
    it "does not issue a query per holding for the security association" do
      3.times { |i| holding(ticker: "S#{i}", market_value: 100 - i) }

      counts = []
      counter = ->(_n, _s, _f, _id, payload) do
        counts << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT")
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/accounts/#{account.id}/holdings", headers: auth_headers
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["positions"].length).to eq(3)

      security_queries = counts.count { |sql| sql.include?("FROM \"securities\"") }
      expect(security_queries).to be <= 1
    end
  end
end
