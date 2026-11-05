require "rails_helper"

RSpec.describe Alchemy::GasDriftSweep do
  let!(:config) { create(:alchemy_configuration, transactions_enabled: true) }
  let!(:wallet) do
    create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001",
                            networks: [ "eth-mainnet" ])
  end
  let(:account) { wallet.ensure_account! }
  let(:eth) do
    Instruments::Resolver.resolve!(instrument_class: "crypto", ticker: "ETH",
                                   name: "Ethereum", security_type: Security::CRYPTO_TYPE)
  end

  before do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id, backfill_status: "completed")
    InstrumentQuote.create!(security: eth, price: 2000, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current)
  end

  def set_state(ledger:, observed:)
    Position.create!(household_id: wallet.household_id, account_id: account.id,
                     security_id: eth.id, quantity: ledger, cost_basis: 0,
                     ledger_updated_at: Time.current)
    PositionSnapshot.create!(household_id: wallet.household_id, account_id: account.id,
                             security: eth, as_of_date: Date.current, quantity: observed,
                             price: 2000, market_value: (observed * 2000).round(2),
                             source_row_hash: "alchemy_wallet:#{wallet.id}:#{eth.id}")
  end

  it "books a GAS transfer-out for gas-sized drift" do
    set_state(ledger: BigDecimal("1.01"), observed: BigDecimal("1.0"))

    result = described_class.new.call
    expect(result.swept).to eq(1)

    txn = InvestmentTransaction.sole
    expect(txn.transaction_type.code).to eq("GAS")
    expect(txn.transaction_type.category).to eq("Transfer Out")
    expect(txn.quantity).to eq(BigDecimal("0.01"))
    expect(txn.amount_usd).to eq(20)
    expect(txn.description).to eq("Accumulated network fees")
  end

  it "ignores drift within reconciliation tolerance" do
    set_state(ledger: BigDecimal("1.000009"), observed: BigDecimal("1.0"))

    expect(described_class.new.call.swept).to eq(0)
    expect(InvestmentTransaction.count).to eq(0)
  end

  it "sweeps multi-year gas accumulation within the 10% cap" do
    set_state(ledger: BigDecimal("1.08"), observed: BigDecimal("1.0"))

    expect(described_class.new.call.swept).to eq(1)
    expect(InvestmentTransaction.sole.quantity).to eq(BigDecimal("0.08"))
  end

  it "leaves implausibly large deltas for reconciliation to flag" do
    set_state(ledger: BigDecimal("2.0"), observed: BigDecimal("1.0"))

    result = described_class.new.call
    expect(result.swept).to eq(0)
    expect(result.skipped).to eq(1)
    expect(InvestmentTransaction.count).to eq(0)
  end

  it "never sweeps when the ledger is below the observation" do
    set_state(ledger: BigDecimal("0.95"), observed: BigDecimal("1.0"))

    expect(described_class.new.call.swept).to eq(0)
  end

  it "waits for backfill to complete" do
    AlchemyWalletSync.sole.update!(backfill_status: "running")
    set_state(ledger: BigDecimal("1.01"), observed: BigDecimal("1.0"))

    expect(described_class.new.call.swept).to eq(0)
  end

  it "books at most one row per day per pair" do
    set_state(ledger: BigDecimal("1.01"), observed: BigDecimal("1.0"))

    described_class.new.call
    # Ledger unchanged (rebuild is async in tests) → same delta, same hash.
    result = described_class.new.call
    expect(result.swept).to eq(0)
    expect(InvestmentTransaction.count).to eq(1)
  end
end
