require "rails_helper"

RSpec.describe Instruments::ConversionDetector do
  let(:today)    { Date.new(2026, 9, 25) }
  let(:global)   { create(:account, name: "Global") }
  let(:purchase) { create(:transaction_type, :purchase) }
  let(:sale)     { create(:transaction_type, :sale) }
  let(:smney)    { create(:security, ticker: "SMNEY", name: "Siemens Energy Ag-Unsp Pay Date 01/30/2026") }
  let(:smery)    { create(:security, ticker: "SMERY", name: "Siemens Energy AG - ADR - Sponsored") }

  around { |ex| travel_to(today) { ex.run } }

  def trade!(security, type, qty, date, account: global)
    create(:investment_transaction, account: account, security: security, transaction_type: type,
           quantity: qty, cost_usd: qty.abs * 10, trade_date: date)
  end

  def close!(security, date, adjusted, raw: adjusted)
    Candle.create!(security: security, date: date, close: raw, adjusted_close: adjusted,
                   currency: "USD", source: "tiingo")
  end

  def report!(security, qty, account: global, price: 32.84)
    create(:position_snapshot, account: account, security: security, as_of_date: today,
           quantity: qty, price: price, market_value: qty * price)
  end

  # Production, 2026-09: SMNEY (unsponsored ADR) became SMERY on 2026-01-30.
  # The ledger recorded neither leg; SMERY then split 5:1 on 2026-06-23.
  def build_siemens!
    trade!(smney, purchase, 613, Date.new(2024, 11, 13))
    trade!(smney, sale, 31, Date.new(2025, 4, 25))
    close!(smney, Date.new(2026, 1, 20), 170.10)
    close!(smney, Date.new(2026, 1, 29), 175.64)

    CorporateAction.create!(security: smery, kind: "split", ex_date: Date.new(2026, 6, 23), ratio: 5, source: "tiingo")
    close!(smery, Date.new(2026, 1, 30), 33.8078, raw: 169.75)
    close!(smery, Date.new(2026, 9, 24), 32.84)
    { Date.new(2026, 2, 26) => 19, Date.new(2026, 2, 27) => 7, Date.new(2026, 3, 2) => 11 }
      .each { |date, qty| trade!(smery, sale, qty, date) } # 37 pre-split
    { Date.new(2026, 7, 13) => 71, Date.new(2026, 8, 12) => 929 }
      .each { |date, qty| trade!(smery, sale, qty, date) } # 1000 post-split
    report!(smery, 1725)
  end

  it "suggests SMNEY -> SMERY at 5 current SMERY shares per SMNEY share, effective the day trading switched" do
    build_siemens!

    created = described_class.new.call

    expect(created.size).to eq(1)
    conversion = created.first
    expect(conversion).to have_attributes(
      from_security: smney, to_security: smery, effective_date: Date.new(2026, 1, 30),
      status: SecurityConversion::Status::Suggested, source: SecurityConversion::Source::Detected
    )
    expect(conversion.ratio).to eq(5)
    expect(conversion.evidence).to include(
      "account_name" => "Global", "ratio_snapped" => true, "shared_name_words" => %w[energy siemens]
    )
    expect(conversion.evidence["to"]).to include("unexplained_quantity" => 2910.0) # 1725 + 37×5 + 1000
    expect(conversion.evidence["value_gap_pct"]).to be < 5
  end

  it "once confirmed, stops valuation counting both lines before the switch" do
    build_siemens!
    value_on = ->(date) { Valuation::PortfolioSeries.call_by_account(from: date, to: today)[global.id][date] }
    before = value_on.(Date.new(2026, 1, 20))

    described_class.new.call.first.confirm!

    after = value_on.(Date.new(2026, 1, 20))
    expect(after).to be < before
    expect(after).to be_within(0.01).of(582 * 170.10) # SMNEY alone at its close that day
  end

  it "is idempotent and never re-suggests a dismissed pair" do
    build_siemens!
    described_class.new.call.first.dismiss!

    expect(described_class.new.call).to be_empty
    expect(SecurityConversion.count).to eq(1)
  end

  it "leaves a holding that still trades alone — that is a missing sell, not a conversion" do
    build_siemens!
    close!(smney, today - 2, 180.0)

    expect(described_class.new.call).to be_empty
  end

  it "ignores a reported holding whose ledger activity predates the old line's last close" do
    build_siemens!
    trade!(smery, sale, 1, Date.new(2026, 1, 15))

    expect(described_class.new.call).to be_empty
  end

  it "needs value continuity when both sides are priced" do
    build_siemens!
    smery.update!(name: "Unrelated Holdings")
    Candle.where(security: smery, date: Date.new(2026, 1, 30)).update_all(adjusted_close: 1.0)

    expect(described_class.new.call).to be_empty
  end

  it "falls back to shared issuer words when the new line has no price to compare" do
    build_siemens!
    Candle.where(security: smery).delete_all

    expect(described_class.new.call.map(&:to_security)).to eq([ smery ])
  end

  it "does not treat a spin-off price adjustment as a share split" do
    build_siemens!
    CorporateAction.create!(security: smery, kind: "split", ex_date: Date.new(2026, 7, 1), ratio: 1.061, source: "tiingo")

    expect(described_class.new.call.first.ratio).to eq(5)
  end
end
