require "rails_helper"

# Query budgets for the read endpoints that fan out over positions and
# transactions. These are ceilings, not targets: they exist so that a change
# which quietly turns one grouped query into one-per-row fails here rather
# than in production. Raise a number only with a reason.
RSpec.describe "Api::V1 query budgets", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:household)    { token.household }

  # Enough rows that a per-row query is unmistakable in the count.
  before do
    broker = create(:broker, household: household)
    accounts = Array.new(3) { create(:account, household: household, broker: broker) }
    securities = Array.new(5) { |i| create(:security, ticker: "Q#{i}", name: "Q#{i} Corp") }

    securities.each_with_index do |security, i|
      create(:market_price, security: security, date: Date.current, close: 100 + i)
    end

    accounts.each do |account|
      securities.each_with_index do |security, i|
        create(:position_snapshot,
               household: household, account: account, security: security,
               as_of_date: Date.current, market_value: 1000 + i,
               cost_basis: 500 + i, quantity: 10)
      end
      5.times do |i|
        create(:cash_transaction, :bank, :debit,
               household: household, account: account,
               transaction_date: Date.current - i.days, amount: -(10 + i))
      end
    end
  end

  # The endpoint, and the ceiling on queries it may issue. Set just above the
  # measured count on this fixture, so growth proportional to the number of
  # holdings trips the budget rather than sliding by.
  {
    "/api/v1/portfolio"         => 22,
    "/api/v1/accounts"          => 18,
    "/api/v1/cash_transactions" => 10,
    "/api/v1/cost_basis"        => 18,
    "/api/v1/net_worth"         => 24, # PortfolioSeries: a fixed handful, not per holding
    "/api/v1/cashflow"          => 32,
    "/api/v1/dashboard"         => 38 # PortfolioSeries: + conversions and splits
  }.each do |path, budget|
    it "serves GET #{path} in at most #{budget} queries" do
      # Warm the request-scoped caches the endpoint would have in a real
      # session, so the budget measures the endpoint and not first-touch setup.
      get path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      expect { get path, headers: auth_headers }.to issue_at_most(budget).queries
    end
  end
end
