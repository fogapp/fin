require "rails_helper"

RSpec.describe SecurityNewsSyncer do
  let(:security) { create(:security, ticker: "COIN", watched: true) }
  let(:client)   { instance_double(AlphaVantage::Client) }

  before { allow(AlphaVantage::Client).to receive(:new).and_return(client) }

  def article(overrides = {})
    # Use a recent published_at so the pruning step doesn't immediately delete the article
    recent_ts = 1.day.ago.strftime("%Y%m%dT%H%M%S")
    { title:           "Test Article",
      url:             "https://news.example.com/#{SecureRandom.hex(4)}",
      source:          "Reuters",
      published_at:    recent_ts,
      summary:         "Summary",
      sentiment:       "Bullish",
      sentiment_score: 0.35 }.merge(overrides)
  end

  def syncer
    described_class.new(security)
  end

  describe "#call" do
    it "upserts articles into SecurityNewsArticle" do
      a = article
      allow(client).to receive(:news_sentiment).and_return([ a ])

      expect { syncer.call }.to change(SecurityNewsArticle, :count).by(1)
    end

    it "does not create a duplicate on re-call with the same URL" do
      a = article
      allow(client).to receive(:news_sentiment).and_return([ a ])

      syncer.call
      expect { syncer.call }.not_to change(SecurityNewsArticle, :count)
    end

    it "skips articles with blank url" do
      a = article(url: "")
      allow(client).to receive(:news_sentiment).and_return([ a ])

      expect { syncer.call }.not_to change(SecurityNewsArticle, :count)
    end

    it "skips articles with blank title" do
      a = article(title: nil)
      allow(client).to receive(:news_sentiment).and_return([ a ])

      expect { syncer.call }.not_to change(SecurityNewsArticle, :count)
    end

    it "deletes articles older than 30 days for that security" do
      old_article = SecurityNewsArticle.create!(
        security:     security,
        title:        "Old news",
        url:          "https://news.example.com/old",
        source:       "Bloomberg",
        published_at: 31.days.ago,
        summary:      "Old summary",
        sentiment:    "Neutral",
        sentiment_score: 0.0
      )
      allow(client).to receive(:news_sentiment).and_return([])

      syncer.call

      expect(SecurityNewsArticle.exists?(old_article.id)).to be false
    end

    it "does not delete recent articles for that security" do
      recent_article = SecurityNewsArticle.create!(
        security:     security,
        title:        "Recent news",
        url:          "https://news.example.com/recent",
        source:       "Reuters",
        published_at: 1.day.ago,
        summary:      "Recent summary",
        sentiment:    "Bullish",
        sentiment_score: 0.4
      )
      allow(client).to receive(:news_sentiment).and_return([])

      syncer.call

      expect(SecurityNewsArticle.exists?(recent_article.id)).to be true
    end

    it "returns the count of articles fetched from the API" do
      articles = [ article, article, article ]
      allow(client).to receive(:news_sentiment).and_return(articles)

      result = syncer.call

      expect(result).to eq(3)
    end

    it "returns 0 when no articles are returned" do
      allow(client).to receive(:news_sentiment).and_return([])

      expect(syncer.call).to eq(0)
    end
  end
end
