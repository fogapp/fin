require "rails_helper"

# Tenancy guardrail: every household-scoped resource must be invisible to a
# token from another household. HouseholdScoped's default_scope is the only
# thing standing between tenants — this matrix fails loudly if a model loses
# the concern or a controller bypasses it.
RSpec.describe "Cross-household isolation", type: :request do
  # Household A is the spec-wide Current.household from spec/support/household_context.rb.
  let(:household_a) { Current.household }

  let(:household_b) { create(:household, name: "Other Household") }
  let(:user_b)      { create(:user, email: "other@example.com") }
  let!(:membership) { create(:household_membership, user: user_b, household: household_b, role: "admin") }
  let(:token_b)     { create(:api_token, user: user_b, household: household_b) }
  let(:headers_b)   { { "Authorization" => "Bearer #{token_b.raw_token}" } }

  # [resource label, record factory (returns record in household A), member path]
  matrix = {
    "accounts" => {
      create: -> { create(:account) },
      path:   ->(r) { "/api/v1/accounts/#{r.id}" }
    },
    "cash_transactions" => {
      create: -> { create(:cash_transaction, :bank, account: create(:account)) },
      path:   ->(r) { "/api/v1/cash_transactions/#{r.id}" }
    },
    "loans" => {
      create: -> { create(:loan) },
      path:   ->(r) { "/api/v1/loans/#{r.id}" }
    },
    "merchants" => {
      create: -> { create(:merchant) },
      path:   ->(r) { "/api/v1/merchants/#{r.id}" }
    },
    "brokers" => {
      create: -> { create(:broker) },
      path:   ->(r) { "/api/v1/brokers/#{r.id}" }
    },
    "categories" => {
      create: -> { create(:category) },
      path:   ->(r) { "/api/v1/categories/#{r.id}" }
    },
    "tags" => {
      create: -> { create(:tag) },
      path:   ->(r) { "/api/v1/tags/#{r.id}" }
    }
  }

  matrix.each do |label, config|
    it "hides household A's #{label} from a household B token" do
      record = instance_exec(&config[:create])
      expect(record.household_id).to eq(household_a.id)

      get config[:path].call(record), headers: headers_b
      expect(response).to have_http_status(:not_found)
    end
  end

  it "hides household A's workflows from a household B token" do
    workflow = create(:workflow)
    get "/api/v1/workflows/#{workflow.id}", headers: headers_b
    expect(response).to have_http_status(:not_found)
  end

  it "keeps provider configurations per household" do
    config_a = CoinbaseConfiguration.unscoped.find_or_initialize_by(household: household_a)
    config_a.update!(api_key_id: "a-key", api_key_secret: "a-secret")

    # B sees its own (unconfigured) record, not A's.
    get "/api/v1/coinbase/configuration", headers: headers_b
    expect(response.parsed_body["configured"]).to be(false)

    # B updating its configuration must not touch A's credentials.
    patch "/api/v1/coinbase/configuration",
          params: { coinbase_configuration: { api_key_id: "b-key", api_key_secret: "b-secret" } },
          headers: headers_b, as: :json
    expect(response).to have_http_status(:ok)

    expect(config_a.reload.api_key_id).to eq("a-key")
    expect(CoinbaseConfiguration.unscoped.where(household: household_b).count).to eq(1)
  end

  it "keeps watchlists, and the market list built from them, per household" do
    security = create(:security, ticker: "NVDA", watched_by: household_a)
    held     = create(:security, ticker: "AMD")
    create(:investment_transaction, security: held) # household A's ledger

    # Securities are shared rows, but which ones B's market page lists (and
    # prices) comes only from B's own holdings, watches and the benchmarks.
    get "/api/v1/market", headers: headers_b
    expect(response.parsed_body.map { |s| s["ticker"] }).not_to include("NVDA", "AMD")

    token_a = create(:api_token) # household A
    get "/api/v1/market", headers: { "Authorization" => "Bearer #{token_a.raw_token}" }
    expect(response.parsed_body.map { |s| s["ticker"] }).to include("NVDA", "AMD")

    expect(security.watched_by?(household_a)).to be(true)
    expect(security.watched_by?(household_b)).to be(false)
  end

  it "scopes api token listings to the requesting user and household" do
    create(:api_token, name: "A token") # household A, user A

    get "/api/v1/api_tokens", headers: headers_b
    names = response.parsed_body.map { |t| t["name"] }
    expect(names).not_to include("A token")
  end
end
