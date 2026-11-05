require "rails_helper"

RSpec.describe AlphaVantage::Client do
  let(:api_key) { "test-key" }
  subject(:client) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "raises MissingKeyError when no key is resolvable" do
      allow(AlphaVantage).to receive(:api_key).and_return(nil)
      expect { described_class.new }.to raise_error(AlphaVantage::MissingKeyError)
      expect { described_class.new(api_key: "") }.to raise_error(AlphaVantage::MissingKeyError)
    end

    it "resolves the key through AlphaVantage.api_key when none is given" do
      allow(AlphaVantage).to receive(:api_key).and_return("resolved-key")
      expect { described_class.new }.not_to raise_error
    end

    it "prefers an explicitly passed key over resolution" do
      allow(AlphaVantage).to receive(:api_key).and_return("resolved-key")
      expect { described_class.new(api_key: "explicit") }.not_to raise_error
      expect(AlphaVantage).not_to have_received(:api_key)
    end
  end

  describe "#daily_time_series" do
    let(:url) { "https://www.alphavantage.co/query?apikey=#{api_key}&function=TIME_SERIES_DAILY&outputsize=compact&symbol=AAPL" }

    it "parses a successful TIME_SERIES_DAILY response" do
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "Meta Data" => { "1. Information" => "Daily Prices" },
          "Time Series (Daily)" => {
            "2025-01-02" => { "1. open" => "100.0", "2. high" => "105.0", "3. low" => "99.0", "4. close" => "102.5", "5. volume" => "1234567" },
            "2025-01-03" => { "1. open" => "102.5", "2. high" => "108.0", "3. low" => "101.0", "4. close" => "107.0", "5. volume" => "2345678" }
          }
        }.to_json
      )

      rows = client.daily_time_series("AAPL")

      expect(rows.size).to eq(2)
      expect(rows.first).to include(date: Date.new(2025, 1, 2), close: BigDecimal("102.5"), volume: 1_234_567)
      expect(rows.first[:open]).to eq(BigDecimal("100.0"))
      expect(rows.first[:high]).to eq(BigDecimal("105.0"))
      expect(rows.first[:low]).to eq(BigDecimal("99.0"))
    end

    it "raises Error when response contains an Error Message" do
      stub_request(:get, url).to_return(status: 200, body: { "Error Message" => "Invalid API call" }.to_json)

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::Error, /Invalid API call/)
    end

    it "raises RateLimitError when response contains a Note" do
      stub_request(:get, url).to_return(status: 200, body: { "Note" => "Thank you for using Alpha Vantage! Our standard API call frequency is 5 calls per minute." }.to_json)

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::RateLimitError, /5 calls per minute/)
    end

    it "raises RateLimitError when response contains an Information field" do
      stub_request(:get, url).to_return(status: 200, body: { "Information" => "free tier limit hit" }.to_json)

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::RateLimitError, /free tier/)
    end

    it "raises Error on unexpected response shape" do
      stub_request(:get, url).to_return(status: 200, body: { "Random" => "thing" }.to_json)

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::Error, /Unexpected/)
    end

    it "raises Error on non-2xx HTTP responses" do
      stub_request(:get, url).to_return(status: 500, body: "internal server error")

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::Error, /HTTP 500/)
    end

    it "raises RateLimitError on HTTP 429" do
      stub_request(:get, url).to_return(status: 429, body: "Too Many Requests")

      expect { client.daily_time_series("AAPL") }.to raise_error(AlphaVantage::RateLimitError, /429/)
    end

    it "passes outputsize=full when requested" do
      full_url = url.sub("outputsize=compact", "outputsize=full")
      stub_request(:get, full_url).to_return(status: 200, body: { "Time Series (Daily)" => {} }.to_json)

      expect(client.daily_time_series("AAPL", outputsize: "full")).to eq([])
    end
  end

  describe "#symbol_search" do
    let(:url) { "https://www.alphavantage.co/query?apikey=#{api_key}&function=SYMBOL_SEARCH&keywords=NVDA" }

    it "parses bestMatches into normalized hashes" do
      stub_request(:get, url).to_return(
        status: 200,
        body: {
          "bestMatches" => [
            { "1. symbol" => "NVDA", "2. name" => "NVIDIA Corporation", "3. type" => "Equity",
              "4. region" => "United States", "8. currency" => "USD", "9. matchScore" => "1.0000" },
            { "1. symbol" => "NVD.FRK", "2. name" => "NVIDIA Corp", "3. type" => "Equity",
              "4. region" => "Frankfurt", "8. currency" => "EUR", "9. matchScore" => "0.6667" }
          ]
        }.to_json
      )

      results = client.symbol_search("NVDA")
      expect(results.size).to eq(2)
      expect(results.first).to include(
        ticker: "NVDA", name: "NVIDIA Corporation", security_type: "Equity",
        region: "United States", currency: "USD", match_score: 1.0
      )
    end

    it "returns [] when bestMatches is missing" do
      stub_request(:get, url).to_return(status: 200, body: {}.to_json)
      expect(client.symbol_search("NVDA")).to eq([])
    end
  end

  describe "#news_sentiment" do
    it "parses a successful NEWS_SENTIMENT response" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "NEWS_SENTIMENT", "tickers" => "COIN"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            "feed" => [
              {
                "title"          => "Big news",
                "url"            => "https://example.com/1",
                "source"         => "Reuters",
                "time_published" => "20250101T120000",
                "summary"        => "Summary text",
                "ticker_sentiment" => [
                  {
                    "ticker"                   => "COIN",
                    "ticker_sentiment_label"   => "Bullish",
                    "ticker_sentiment_score"   => "0.35"
                  }
                ]
              }
            ]
          }.to_json
        )

      result = client.news_sentiment("COIN")

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      article = result.first
      expect(article[:title]).to eq("Big news")
      expect(article[:url]).to eq("https://example.com/1")
      expect(article[:source]).to eq("Reuters")
      expect(article[:published_at]).to eq("20250101T120000")
      expect(article[:summary]).to eq("Summary text")
      expect(article[:sentiment]).to eq("Bullish")
      expect(article[:sentiment_score]).to eq(0.35)
    end

    it "returns empty array when feed key is absent" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "NEWS_SENTIMENT"))
        .to_return(status: 200, body: { "meta" => "data" }.to_json)

      expect(client.news_sentiment("COIN")).to eq([])
    end

    it "returns empty array when feed is not an array" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "NEWS_SENTIMENT"))
        .to_return(status: 200, body: { "feed" => "not an array" }.to_json)

      expect(client.news_sentiment("COIN")).to eq([])
    end
  end

  # Rate-limit notices arrive as 200 OK with a Note/Information body; the
  # check runs inside the shared get so no endpoint can misreport a rate
  # limit as "no data".
  describe "rate limits on non-time-series endpoints" do
    it "raises RateLimitError from fx_rate instead of returning nil" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "CURRENCY_EXCHANGE_RATE"))
        .to_return(status: 200, body: { "Note" => "5 calls per minute" }.to_json)

      expect { client.fx_rate("EUR") }.to raise_error(AlphaVantage::RateLimitError)
    end

    it "raises RateLimitError from company_overview instead of returning nil" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "OVERVIEW"))
        .to_return(status: 200, body: { "Information" => "free tier limit hit" }.to_json)

      expect { client.company_overview("AAPL") }.to raise_error(AlphaVantage::RateLimitError)
    end

    it "raises RateLimitError from news_sentiment instead of returning []" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "NEWS_SENTIMENT"))
        .to_return(status: 200, body: { "Note" => "5 calls per minute" }.to_json)

      expect { client.news_sentiment("COIN") }.to raise_error(AlphaVantage::RateLimitError)
    end

    it "raises RateLimitError from symbol_search instead of returning []" do
      stub_request(:get, /alphavantage\.co/)
        .with(query: hash_including("function" => "SYMBOL_SEARCH"))
        .to_return(status: 200, body: { "Information" => "free tier limit hit" }.to_json)

      expect { client.symbol_search("NVDA") }.to raise_error(AlphaVantage::RateLimitError)
    end
  end
end
