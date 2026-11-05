require "rails_helper"

RSpec.describe CoinMarketCap::Client do
  describe ".new" do
    it "raises MissingKeyError when no key is configured and ENV is unset" do
      CoinMarketCapConfiguration.delete_all
      original = ENV.delete("COINMARKETCAP_API_KEY")
      expect { described_class.new }.to raise_error(CoinMarketCap::MissingKeyError, /not configured/)
    ensure
      ENV["COINMARKETCAP_API_KEY"] = original if original
    end

    it "accepts an explicit key parameter" do
      expect { described_class.new(api_key: "k") }.not_to raise_error
    end
  end

  describe "#quotes" do
    let(:client) { described_class.new(api_key: "test-key") }

    it "GETs /v2/cryptocurrency/quotes/latest and returns ticker => price" do
      stub_request(:get, %r{pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest})
        .with(query: hash_including(symbol: "BTC,ETH", convert: "USD"),
              headers: { "X-CMC_PRO_API_KEY" => "test-key" })
        .to_return(
          status: 200,
          body: {
            "data" => {
              "BTC" => [ { "slug" => "bitcoin",  "quote" => { "USD" => { "price" => 50_000.0 } } } ],
              "ETH" => [ { "slug" => "ethereum", "quote" => { "USD" => { "price" => 3_000.0  } } } ]
            }
          }.to_json
        )

      expect(client.quotes(%w[BTC ETH])).to eq("BTC" => 50_000.0, "ETH" => 3_000.0)
    end

    it "returns an empty hash for an empty symbols list" do
      expect(client.quotes([])).to eq({})
    end
  end

  describe "#quote_data" do
    let(:client) { described_class.new(api_key: "test-key") }

    it "returns ticker => { price:, slug: }" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 200, body: {
          "data" => {
            "BTC" => [ { "slug" => "bitcoin", "quote" => { "USD" => { "price" => 50_000.0 } } } ]
          }
        }.to_json)

      expect(client.quote_data(%w[BTC])).to eq("BTC" => { price: 50_000.0, slug: "bitcoin" })
    end

    it "omits symbols with no USD price in the response" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 200, body: {
          "data" => {
            "BTC" => [ { "slug" => "bitcoin", "quote" => { "USD" => { "price" => 50_000.0 } } } ],
            "UNKNOWN" => [ { "slug" => "unknown", "quote" => {} } ]
          }
        }.to_json)

      expect(client.quote_data(%w[BTC UNKNOWN])).to eq("BTC" => { price: 50_000.0, slug: "bitcoin" })
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 429, body: { "status" => { "error_message" => "limit" } }.to_json)

      expect { client.quote_data(%w[BTC]) }.to raise_error(CoinMarketCap::RateLimitError)
    end

    it "raises RateLimitError on a 429 whose body isn't JSON" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 429, body: "<html><body>Too Many Requests</body></html>")

      expect { client.quote_data(%w[BTC]) }.to raise_error(CoinMarketCap::RateLimitError)
    end

    it "raises Error with a body excerpt when an error response isn't JSON" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 502, body: "<html>Bad Gateway</html>")

      expect { client.quote_data(%w[BTC]) }.to raise_error(CoinMarketCap::Error, /502: <html>Bad Gateway/)
    end

    it "raises Error (not JSON::ParserError) on a non-JSON success body" do
      stub_request(:get, %r{pro-api.coinmarketcap.com}).to_return(status: 200, body: "oops")

      expect { client.quote_data(%w[BTC]) }.to raise_error(CoinMarketCap::Error, /non-JSON/)
    end

    it "raises Error with the status error_message on other failures" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 401, body: { "status" => { "error_message" => "bad key" } }.to_json)

      expect { client.quote_data(%w[BTC]) }.to raise_error(CoinMarketCap::Error, /401: bad key/)
    end
  end
end
