require "rails_helper"

# The suite runs on a null cache store, so render_cached is transparent
# everywhere else; this spec swaps in a real store to prove the contract:
# repeat reads are served from cache, financial writes rotate the key.
RSpec.describe "Endpoint caching", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  it "serves repeat reads from cache and recomputes after a financial write" do
    account = create(:account, account_type: "Checking", balance: 1000, balance_usd: 1000)

    expect(NetWorthHistory).to receive(:new).once.and_call_original
    get "/api/v1/net_worth", headers: auth_headers
    get "/api/v1/net_worth", headers: auth_headers
    expect(response).to have_http_status(:ok)

    # A committed write bumps the household DataVersion → cache key rotates.
    create(:cash_transaction, account: account)

    expect(NetWorthHistory).to receive(:new).once.and_call_original
    get "/api/v1/net_worth", headers: auth_headers
    expect(response).to have_http_status(:ok)
  end

  it "keys the cache on query parameters" do
    expect(NetWorthHistory).to receive(:new).twice.and_call_original
    get "/api/v1/net_worth", params: { range: "3m" }, headers: auth_headers
    get "/api/v1/net_worth", params: { range: "1y" }, headers: auth_headers
    expect(response).to have_http_status(:ok)
  end

  it "ignores params outside the endpoint's whitelist, so stray params can't fork entries" do
    expect(NetWorthHistory).to receive(:new).once.and_call_original
    get "/api/v1/net_worth", params: { range: "3m" }, headers: auth_headers
    get "/api/v1/net_worth", params: { range: "3m", utm_source: "newsletter" }, headers: auth_headers
    expect(response).to have_http_status(:ok)
  end

  it "serves 304 Not Modified on a matching ETag and recomputes after a write" do
    account = create(:account, account_type: "Checking", balance: 1000, balance_usd: 1000)

    get "/api/v1/net_worth", headers: auth_headers
    etag = response.headers["ETag"]
    expect(etag).to be_present

    get "/api/v1/net_worth", headers: auth_headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_blank

    # A committed financial write rotates the DataVersion, so the old ETag
    # stops matching and the payload is recomputed.
    create(:cash_transaction, account: account)
    get "/api/v1/net_worth", headers: auth_headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:ok)
    expect(response.headers["ETag"]).not_to eq(etag)
  end

  it "rotates the ETag when the deployed code changes, so no client can replay an old payload shape" do
    get "/api/v1/net_worth", headers: auth_headers
    etag = response.headers["ETag"]

    stub_const("Api::ResponseCache::CODE_VERSION", "deadbeef")

    get "/api/v1/net_worth", headers: auth_headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:ok)
    expect(response.headers["ETag"]).not_to eq(etag)
  end

  it "caches /budget and rotates when a budget line changes" do
    category = create(:category, name: "Groceries", budget_kind: "flex")

    get "/api/v1/budget", headers: auth_headers
    etag = response.headers["ETag"]
    get "/api/v1/budget", headers: auth_headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:not_modified)

    BudgetLine.create!(household_id: token.household_id, category: category,
                       month: Date.current.beginning_of_month, planned: 100)

    get "/api/v1/budget", headers: auth_headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["lines"].sole["category_name"]).to eq("Groceries")
  end
end
