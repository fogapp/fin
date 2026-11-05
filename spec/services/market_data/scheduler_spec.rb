require "rails_helper"

RSpec.describe MarketData::Scheduler do
  let(:account) { create(:account) }

  def scheduler(budgets = { MarketData::Provider::AlphaVantage => 10, MarketData::Provider::CoinGecko => 10 })
    described_class.new(budgets: budgets, pace: false)
  end

  def hold!(security)
    create(:position_snapshot, account: account, security: security,
           as_of_date: Date.current, quantity: 1,
           source_row_hash: "csv-#{security.id}")
  end

  before { allow(MarketData::Router).to receive(:provider_instance).and_call_original }

  def stub_provider(provider_key, klass)
    fake = instance_double(klass, sync_candles: 1)
    allow(MarketData::Router).to receive(:provider_instance).with(provider_key).and_return(fake)
    fake
  end

  it "routes crypto to coin_gecko and equities to alpha_vantage, creating links" do
    coin  = create(:security, ticker: "BTC", instrument_class: "crypto")
    stock = create(:security, ticker: "AAPL", instrument_class: "equity")
    hold!(coin)
    hold!(stock)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)
    cg = stub_provider(MarketData::Provider::CoinGecko, MarketData::Providers::CoinGecko)

    result = scheduler.run

    expect(result.synced).to eq(2)
    expect(av).to have_received(:sync_candles).with(stock, anything, full: true)
    expect(cg).to have_received(:sync_candles).with(coin, anything, full: true)
    expect(InstrumentDataLink.pluck(:provider))
      .to contain_exactly(MarketData::Provider::AlphaVantage, MarketData::Provider::CoinGecko)
  end

  it "syncs dormant instruments never — only held, watched, and benchmarks" do
    held      = create(:security, ticker: "AAPL", instrument_class: "equity")
    watched   = create(:security, ticker: "MSFT", instrument_class: "equity")
    benchmark = create(:security, ticker: "SPY", instrument_class: "etf")
    _dormant  = create(:security, ticker: "JUNK", instrument_class: "equity")
    hold!(held)
    SecurityWatch.create!(security: watched, household: Current.household)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

    scheduler.run

    synced = []
    expect(av).to have_received(:sync_candles).exactly(3).times do |sec, *|
      synced << sec.ticker
    end
    expect(synced).to contain_exactly("AAPL", "MSFT", "SPY")
  end

  it "spends the provider budget on held instruments first" do
    held    = create(:security, ticker: "AAPL", instrument_class: "equity")
    watched = create(:security, ticker: "MSFT", instrument_class: "equity")
    hold!(held)
    SecurityWatch.create!(security: watched, household: Current.household)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

    scheduler(MarketData::Provider::AlphaVantage => 1).run

    expect(av).to have_received(:sync_candles).once do |sec, *|
      expect(sec.ticker).to eq("AAPL")
    end
  end

  it "backs off failing links exponentially and records failures" do
    sec = create(:security, ticker: "BAD", instrument_class: "equity")
    hold!(sec)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)
    allow(av).to receive(:sync_candles).and_raise(RuntimeError, "boom")

    result = scheduler.run
    expect(result.failed).to eq(1)

    link = InstrumentDataLink.sole
    expect(link.consecutive_failures).to eq(1)
    expect(link.last_error).to match(/boom/)
    expect(link.in_backoff?).to be(true)

    # In backoff → skipped, provider not called again
    result2 = scheduler.run
    expect(result2.skipped).to eq(1)
    expect(av).to have_received(:sync_candles).once
  end

  it "treats a provider rate limit as provider-wide: zeroes the budget, no link failure, no sync stamp" do
    AlphaVantage::Client # load the module so its error classes are defined
    a = create(:security, ticker: "AAA", instrument_class: "equity")
    b = create(:security, ticker: "BBB", instrument_class: "equity")
    hold!(a)
    hold!(b)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)
    allow(av).to receive(:sync_candles).and_raise(AlphaVantage::RateLimitError, "throttled")

    result = scheduler.run

    # Budget zeroed after the first hit — the second instrument never burns a call.
    expect(av).to have_received(:sync_candles).once
    expect(result.skipped).to eq(1)
    expect(result.failed).to eq(0)
    # No link is punished into backoff, and staleness stays visible.
    expect(InstrumentDataLink.pluck(:consecutive_failures)).to all(eq(0))
    expect(Security.where.not(last_synced_at: nil)).to be_empty
  end

  it "never stamps last_synced_at on a per-instrument failure" do
    sec = create(:security, ticker: "BAD", instrument_class: "equity")
    hold!(sec)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)
    allow(av).to receive(:sync_candles).and_raise(RuntimeError, "boom")

    scheduler.run

    expect(sec.reload.last_synced_at).to be_nil
    expect(InstrumentDataLink.sole.consecutive_failures).to eq(1)
  end

  it "requests a full backfill only when the instrument has no candles" do
    sec = create(:security, ticker: "AAPL", instrument_class: "equity")
    hold!(sec)
    Candle.create!(security: sec, date: Date.current, close: 100, currency: "USD", source: "alpha_vantage")
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

    scheduler.run

    expect(av).to have_received(:sync_candles).with(sec, anything, full: false)
  end

  it "never syncs unpriceable classes (bonds, cash)" do
    bond = create(:security, ticker: "BOND1", instrument_class: "bond")
    hold!(bond)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

    result = scheduler.run

    expect(result.synced).to eq(0)
    expect(av).not_to have_received(:sync_candles)
    expect(InstrumentDataLink.count).to eq(0)
  end

  describe "recently sold instruments" do
    let(:sale_type) { create(:transaction_type, :sale) }

    def trade!(security, date)
      create(:investment_transaction, account: account, security: security, trade_date: date, quantity: 5,
                                      transaction_type: sale_type)
    end

    it "backfills history once for instruments traded in the last two years" do
      sold    = create(:security, ticker: "MSCI", instrument_class: "equity")
      ancient = create(:security, ticker: "OLD", instrument_class: "equity")
      trade!(sold, Date.current - 200)
      trade!(ancient, Date.current - (3 * 365))
      av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

      scheduler.run

      expect(av).to have_received(:sync_candles).once
      expect(av).to have_received(:sync_candles).with(sold, anything, full: true)
    end

    it "stops once provider history exists, or the provider answered with none" do
      priced  = create(:security, ticker: "TER", instrument_class: "equity")
      empty   = create(:security, ticker: "SMNEY", instrument_class: "equity")
      trade!(priced, Date.current - 30)
      trade!(empty, Date.current - 30)
      Candle.create!(security: priced, date: Date.current - 40, close: 100, currency: "USD", source: "alpha_vantage")
      InstrumentDataLink.create!(security: empty, capability: MarketData::Capability::Candles,
                                 provider: MarketData::Provider::AlphaVantage, last_success_at: 1.day.ago)
      av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

      scheduler.run

      expect(av).not_to have_received(:sync_candles)
    end
  end

  it "requests a full backfill when the only candles are custodian-reported" do
    sec = create(:security, ticker: "AAPL", instrument_class: "equity")
    hold!(sec)
    Candle.create!(security: sec, date: Date.current, close: 100, currency: "USD", source: MarketData::CustodianPrices::SOURCE)
    av = stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)

    scheduler.run

    expect(av).to have_received(:sync_candles).with(sec, anything, full: true)
  end

  it "reads every instrument's link in one query, not one per instrument" do
    securities = %w[AAPL MSFT NVDA].map { |t| create(:security, ticker: t, instrument_class: "equity") }
    securities.each { |s| hold!(s) }
    stub_provider(MarketData::Provider::AlphaVantage, MarketData::Providers::AlphaVantage)
    scheduler.run # pins the links

    queries = count_queries { scheduler.run }

    link_reads = queries.grep(/SELECT "instrument_data_links".* FROM "instrument_data_links"/)
    expect(link_reads.size).to eq(1)
    expect(link_reads.first).to include("IN (")
  end
end
