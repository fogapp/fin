require "rails_helper"

RSpec.describe Instruments::Resolver do
  describe "class-scoped symbol schemes" do
    it "keeps BTC-the-coin and BTC-the-ETF as separate instruments forever" do
      coin = described_class.resolve!(instrument_class: "crypto", ticker: "BTC", name: "Bitcoin")
      etf  = described_class.resolve!(instrument_class: "etf", ticker: "BTC", name: "Grayscale Bitcoin Mini Trust")

      expect(coin.id).not_to eq(etf.id)
      expect(coin.instrument_class).to eq(Instruments::InstrumentClass::Crypto)
      expect(etf.instrument_class).to eq(Instruments::InstrumentClass::Etf)

      # and resolution is stable in both directions
      expect(described_class.resolve!(instrument_class: "crypto", ticker: "btc").id).to eq(coin.id)
      expect(described_class.resolve!(instrument_class: "etf", ticker: "BTC").id).to eq(etf.id)
    end

    it "shares the ticker scheme across non-crypto classes (equity watch finds the ETF row)" do
      etf = described_class.resolve!(instrument_class: "etf", ticker: "SPY")
      watched = described_class.resolve!(instrument_class: "equity", ticker: "SPY")
      expect(watched.id).to eq(etf.id)
    end
  end

  describe "normalization" do
    it "upcases and strips tickers so case never forks identity" do
      a = described_class.resolve!(instrument_class: "crypto", ticker: "cbETH")
      b = described_class.resolve!(instrument_class: "crypto", ticker: " CBETH ")
      expect(b.id).to eq(a.id)
      expect(a.ticker).to eq("CBETH")
    end
  end

  describe "strong identifiers" do
    it "resolves by cusip first and backfills the ticker identifier" do
      existing = described_class.resolve!(instrument_class: "equity", cusip: "037833100", name: "Apple")
      hit = described_class.resolve!(instrument_class: "equity", ticker: "AAPL", cusip: "037833100")

      expect(hit.id).to eq(existing.id)
      expect(described_class.resolve!(instrument_class: "equity", ticker: "AAPL").id).to eq(existing.id)
    end

    it "resolves by plaid_security_id when tickers are absent" do
      created = described_class.resolve!(instrument_class: "equity", name: "Mystery Bond Fund",
                                         identifiers: { plaid_security_id: "plaid-sec-1" })
      hit = described_class.resolve!(instrument_class: "equity",
                                     identifiers: { plaid_security_id: "plaid-sec-1" })
      expect(hit.id).to eq(created.id)
    end

    it "backfills a missing cusip onto a ticker-resolved row" do
      bare = described_class.resolve!(instrument_class: "equity", ticker: "MSFT")
      expect(bare.cusip).to be_nil

      hit = described_class.resolve!(instrument_class: "equity", ticker: "MSFT", cusip: "594918104")
      expect(hit.id).to eq(bare.id)
      expect(hit.reload.cusip).to eq("594918104")
    end

    it "backfills a missing cusip column onto a plaid_security_id hit" do
      bond = described_class.resolve!(instrument_class: "bond", name: "San Fran Ca 4.0%07/01/27",
                                      identifiers: { plaid_security_id: "plaid-muni-1" })
      expect(bond.cusip).to be_nil

      hit = described_class.resolve!(instrument_class: "bond", cusip: "797669WT1",
                                     identifiers: { plaid_security_id: "plaid-muni-1" })
      expect(hit.id).to eq(bond.id)
      expect(hit.reload.cusip).to eq("797669WT1")
    end

    it "leaves the cusip column alone when another row already owns that cusip" do
      owner = create(:security, :without_ticker, cusip: "797669WT1")
      other = described_class.resolve!(instrument_class: "bond", name: "Muni", identifiers: { plaid_security_id: "plaid-muni-2" })

      hit = described_class.resolve!(instrument_class: "bond", cusip: "797669WT1",
                                     identifiers: { plaid_security_id: "plaid-muni-2" })

      expect(hit.id).to eq(owner.id).or eq(other.id)
      expect(other.reload.cusip).to be_nil
    end
  end

  describe "reclassification" do
    it "adopts a source's Bond class for a tickerless row a CSV import guessed as Equity/Other" do
      guessed = described_class.resolve!(instrument_class: "equity", name: "California St Univ Rev 5% 11/01/32",
                                         identifiers: { plaid_security_id: "plaid-muni-3" })

      described_class.resolve!(instrument_class: "bond", identifiers: { plaid_security_id: "plaid-muni-3" })

      expect(guessed.reload).to have_attributes(instrument_class: Instruments::InstrumentClass::Bond,
                                                security_type: "Fixed Income")
    end

    it "never reclassifies a listed (ticker-bearing) row" do
      listed = described_class.resolve!(instrument_class: "equity", ticker: "BND2", identifiers: { plaid_security_id: "plaid-4" })

      described_class.resolve!(instrument_class: "bond", identifiers: { plaid_security_id: "plaid-4" })

      expect(listed.reload.instrument_class).to eq(Instruments::InstrumentClass::Equity)
    end
  end

  describe "conflicts" do
    it "creates a separate instrument and raises an Issue when cusips disagree" do
      described_class.resolve!(instrument_class: "equity", ticker: "ETH", cusip: "111111111",
                               name: "Ethan Allen")

      other = described_class.resolve!(instrument_class: "equity", ticker: "ETH", cusip: "222222222")

      expect(other.cusip).to eq("222222222")
      expect(Security.where(ticker: "ETH").count).to eq(2)
      expect(Issue.active.where("key LIKE 'instrument_conflict:%'")).to exist
    end
  end

  it "rejects unknown instrument classes" do
    expect {
      described_class.resolve!(instrument_class: "weather", ticker: "X")
    }.to raise_error(ArgumentError)
  end

  describe "concurrent create races" do
    # Both tests simulate a concurrent resolve! that registered the same
    # identifier between this call's lookup miss and its registration. The
    # loser must adopt the winner and destroy its just-created duplicate
    # instead of keeping an identifier-less Security.
    let!(:winner) { create(:security, ticker: "AAPL", instrument_class: "equity") }

    before do
      # The initial resolution lookup misses (the racer hadn't committed yet);
      # later lookups see the truth.
      calls = 0
      allow(described_class).to receive(:find_by_identifier).and_wrap_original do |m, scheme, value|
        calls += 1
        next nil if calls == 1 && scheme == InstrumentIdentifier::Scheme::Ticker && value == "AAPL"
        m.call(scheme, value)
      end
    end

    # Security's after_create auto-registers its ticker identifier, so the
    # winner's "ticker"=>"AAPL" identifier row already exists in both tests.

    it "adopts the winner after losing the identifier INSERT race (RecordNotUnique)" do
      raised = false
      allow(InstrumentIdentifier).to receive(:find_or_create_by!).and_wrap_original do |m, *args, &blk|
        unless raised
          raised = true
          raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint"
        end
        m.call(*args, &blk)
      end

      resolved = described_class.resolve!(instrument_class: "equity", ticker: "AAPL")

      expect(resolved.id).to eq(winner.id)
      expect(Security.where(ticker: "AAPL").count).to eq(1)
    end

    it "adopts the winner when the racer's identifier lands before registration (find branch)" do
      resolved = described_class.resolve!(instrument_class: "equity", ticker: "AAPL")

      expect(resolved.id).to eq(winner.id)
      expect(Security.where(ticker: "AAPL").count).to eq(1)
      expect(InstrumentIdentifier.where(scheme: "ticker", value: "AAPL").sole.security_id).to eq(winner.id)
    end
  end
end
