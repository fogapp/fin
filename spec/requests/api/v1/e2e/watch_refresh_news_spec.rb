require "rails_helper"

# E2E flow: a user adds a security to their watchlist, refreshes its prices,
# and pulls news. Exercises securities#watch → SyncSecurityPricesJob enqueue,
# securities#refresh → background job enqueues (the AlphaVantage calls no
# longer run inline; the jobs own rate-limit retries), and securities#news
# returning rows from SecurityNewsArticle.
RSpec.describe "E2E: watch → refresh → news", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  before { ENV["ALPHA_VANTAGE_API_KEY"] = "test-key" }
  after  { ENV.delete("ALPHA_VANTAGE_API_KEY") }

  describe "with the AlphaVantage key configured" do
    it "watches a new ticker and enqueues the price + overview sync jobs" do
      expect {
        post "/api/v1/market/watch", params: { ticker: "msft", name: "Microsoft" },
             headers: auth_headers, as: :json
      }.to change(Security, :count).by(1)
        .and have_enqueued_job(SyncSecurityPricesJob)
        .and have_enqueued_job(SyncSecurityOverviewJob)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ticker"]).to eq("MSFT")
      expect(body["watched"]).to be true
      expect(Security.find_by(ticker: "MSFT").watched_by?(token.household)).to be true
    end

    it "enqueues the price and overview sync jobs on refresh instead of calling AlphaVantage inline" do
      sec = create(:security, ticker: "MSFT", instrument_class: "equity", watched: true)

      expect {
        post "/api/v1/market/MSFT/refresh", headers: auth_headers
      }.to have_enqueued_job(SyncSecurityPricesJob).with(sec.id)
        .and have_enqueued_job(SyncSecurityOverviewJob).with(sec.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "syncing", "ticker" => "MSFT", "syncing" => true)
    end

    it "skips the overview job for crypto securities on refresh" do
      create(:security, ticker: "BTC", security_type: "Crypto", instrument_class: "crypto", watched: true)

      expect {
        post "/api/v1/market/BTC/refresh", headers: auth_headers
      }.to have_enqueued_job(SyncSecurityPricesJob)
      expect(SyncSecurityOverviewJob).not_to have_been_enqueued

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["syncing"]).to be true
    end
  end

  describe "without the AlphaVantage key" do
    before { ENV.delete("ALPHA_VANTAGE_API_KEY") }

    it "does not enqueue sync jobs on watch" do
      expect {
        post "/api/v1/market/watch", params: { ticker: "MSFT", name: "Microsoft" },
             headers: auth_headers, as: :json
      }.not_to have_enqueued_job(SyncSecurityPricesJob)
      expect(response).to have_http_status(:ok)
    end

    it "still syncs prices when only Tiingo is configured (no overview job)" do
      allow(Tiingo).to receive(:configured?).and_return(true)

      expect {
        post "/api/v1/market/watch", params: { ticker: "MSFT", name: "Microsoft" },
             headers: auth_headers, as: :json
      }.to have_enqueued_job(SyncSecurityPricesJob)
      expect(SyncSecurityOverviewJob).not_to have_been_enqueued
    end

    it "returns 422 on refresh" do
      create(:security, ticker: "MSFT")
      post "/api/v1/market/MSFT/refresh", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/not configured/)
    end
  end

  describe "DELETE /api/v1/market/:id/unwatch" do
    it "flips watched to false" do
      sec = create(:security, ticker: "MSFT", instrument_class: "equity", watched: true)
      delete "/api/v1/market/MSFT/unwatch", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(sec.reload.watched_by?(token.household)).to be false
    end
  end

  describe "GET /api/v1/market/:id/news" do
    it "returns news articles ordered most recent first" do
      sec = create(:security, ticker: "MSFT", instrument_class: "equity", watched: true)
      sec.news_articles.create!(title: "Old",     url: "https://x/1", source: "Reuters",
                                 published_at: 2.days.ago, summary: "old", sentiment: "neutral",
                                 sentiment_score: 0.0)
      sec.news_articles.create!(title: "Newer",   url: "https://x/2", source: "WSJ",
                                 published_at: 1.day.ago,  summary: "newer", sentiment: "bullish",
                                 sentiment_score: 0.7)

      get "/api/v1/market/MSFT/news", headers: auth_headers
      expect(response).to have_http_status(:ok)
      titles = response.parsed_body.map { |a| a["title"] }
      expect(titles).to eq([ "Newer", "Old" ])
      expect(response.parsed_body.first["sentiment_score"]).to eq(0.7)
    end

    it "returns 404 for an unknown ticker" do
      get "/api/v1/market/UNKNOWN/news", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
