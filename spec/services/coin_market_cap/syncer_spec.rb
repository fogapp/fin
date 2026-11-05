require "rails_helper"

RSpec.describe CoinMarketCap::Syncer do
  # The syncer's T.let cast in #initialize rejects instance_double, so we hand
  # it a real Client with an api_key and stub the API calls on the instance.
  let(:client) { CoinMarketCap::Client.new(api_key: "test-key") }

  before { allow(CoinMarketCap::Client).to receive(:new).and_return(client) }

  def stub_quote_data(map)
    allow(client).to receive(:quote_data).and_return(map)
  end

  describe "#call" do
    it "returns an empty result and skips API call when no symbols qualify" do
      expect(client).not_to receive(:quote_data)

      result = described_class.new.call
      expect(result.updated).to eq(0)
      expect(result.skipped).to eq(0)
      expect(result.errors).to  eq([])
    end

    it "updates balance_usd and snapshots non-USD crypto accounts" do
      coinbase = create(:broker, name: "Coinbase")
      account  = create(:account, broker: coinbase, account_type: "crypto", balance: 0.5, balance_currency: "BTC")

      stub_quote_data("BTC" => { price: 50_000.0, slug: "bitcoin" })

      expect { described_class.new.call }
        .to change { account.reload.balance_usd }.to(25_000.0)
        .and change(AccountBalanceSnapshot, :count).by(1)
    end

    it "skips accounts whose currency has no price and records them in result.skipped" do
      coinbase = create(:broker, name: "Coinbase")
      create(:account, broker: coinbase, account_type: "crypto", balance: 0.5, balance_currency: "OBSCURE")

      stub_quote_data({})

      result = described_class.new.call
      expect(result.skipped).to eq(1)
    end

    it "upserts daily MarketPrice rows for each watched crypto" do
      sec = create(:security, ticker: "BTC", security_type: "Crypto", watched: true)
      stub_quote_data("BTC" => { price: 50_000.0, slug: "bitcoin" })

      expect { described_class.new.call }.to change { MarketPrice.where(security_id: sec.id, date: Date.current).count }.by(1)
      mp = MarketPrice.find_by!(security_id: sec.id, date: Date.current)
      expect(mp.close).to eq(50_000.0)
    end

    it "quotes held crypto that isn't on the watchlist" do
      coinbase = create(:broker, name: "Coinbase")
      create(:account, broker: coinbase, account_type: "crypto", balance: 0.5, balance_currency: "BTC")
      sec = create(:security, ticker: "BTC", security_type: "Crypto", watched: false)

      stub_quote_data("BTC" => { price: 50_000.0, slug: "bitcoin" })

      expect { described_class.new.call }
        .to change { MarketPrice.where(security_id: sec.id, date: Date.current).count }.by(1)
    end

    it "ignores crypto that is neither watched nor held" do
      sec = create(:security, ticker: "DOGE", security_type: "Crypto", watched: false)
      stub_quote_data("DOGE" => { price: 0.4, slug: "dogecoin" })

      expect { described_class.new.call }
        .not_to change { MarketPrice.where(security_id: sec.id).count }
    end

    it "updates the security slug when the API returns one" do
      sec = create(:security, ticker: "BTC", security_type: "Crypto", watched: true, slug: nil)
      stub_quote_data("BTC" => { price: 50_000.0, slug: "bitcoin" })

      described_class.new.call
      expect(sec.reload.slug).to eq("bitcoin")
    end

    it "upserts a Coinbase-specific PositionSnapshot for crypto holdings" do
      coinbase = create(:broker, name: "Coinbase")
      account  = create(:account, broker: coinbase, account_type: "crypto", balance: 2.0, balance_currency: "ETH")
      sec      = create(:security, ticker: "ETH", security_type: "Crypto", watched: true)

      stub_quote_data("ETH" => { price: 3_000.0, slug: "ethereum" })

      expect { described_class.new.call }
        .to change { PositionSnapshot.where(account_id: account.id, security_id: sec.id).count }.by(1)

      snap = PositionSnapshot.find_by!(account_id: account.id, security_id: sec.id)
      expect(snap.quantity).to     eq(2.0)
      expect(snap.market_value).to eq(6_000.0)
      expect(snap.source_row_hash).to include("computed:coinbase:")
    end

    it "skips position upserts when the Coinbase broker doesn't exist" do
      create(:account, account_type: "crypto", balance: 2.0, balance_currency: "ETH")
      create(:security, ticker: "ETH", security_type: "Crypto", watched: true)
      stub_quote_data("ETH" => { price: 3_000.0, slug: "ethereum" })

      expect { described_class.new.call }.not_to change(PositionSnapshot, :count)
    end

    it "captures per-account errors" do
      coinbase = create(:broker, name: "Coinbase")
      account  = create(:account, broker: coinbase, account_type: "crypto", balance: 1.0, balance_currency: "BTC")
      stub_quote_data("BTC" => { price: 50_000.0, slug: "bitcoin" })

      allow(AccountBalanceSnapshot).to receive(:record).and_raise("disk full")

      result = described_class.new.call
      expect(result.errors).to include(hash_including(account: account.name, error: "disk full"))
    end
  end
end
