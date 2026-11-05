require "rails_helper"

RSpec.describe Alchemy::TransferIngestor do
  let!(:wallet) { create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001") }
  let(:eth) do
    Instruments::Resolver.resolve!(instrument_class: "crypto", ticker: "ETH",
                                   name: "Ethereum", security_type: Security::CRYPTO_TYPE)
  end

  before do
    Candle.create!(security: eth, date: Date.new(2026, 7, 10), close: 2000,
                   currency: "USD", source: "coin_gecko")
  end

  def raw_transfer(overrides = {})
    {
      "uniqueId"    => "0xdeadbeef:external",
      "hash"        => "0xdeadbeef",
      "blockNum"    => "0xf4240",
      "from"        => "0xBBB0000000000000000000000000000000000002",
      "to"          => wallet.address.upcase,
      "value"       => 1.5,
      "asset"       => "ETH",
      "category"    => "external",
      "rawContract" => { "value" => "0x#{(15 * 10**17).to_s(16)}", "address" => nil, "decimal" => "0x12" },
      "metadata"    => { "blockTimestamp" => "2026-07-10T12:00:00Z" }
    }.merge(overrides)
  end

  it "ingests a batch, counting created/duplicate/skipped and touched pairs" do
    transfers = [
      raw_transfer,
      raw_transfer, # duplicate of the first
      raw_transfer("uniqueId" => "0xfeed:external", "value" => 0,
                   "rawContract" => { "value" => "0x0", "address" => nil, "decimal" => "0x12" })
    ]

    result = described_class.new.call(wallet: wallet, network: "eth-mainnet", raw_transfers: transfers)

    expect(result.created).to eq(1)
    expect(result.duplicates).to eq(1)
    expect(result.skipped).to eq(skipped_zero: 1)
    expect(result.touched_pairs).to eq(Set[[ wallet.reload.account.id, eth.id ]])
  end

  it "issues page-level lookups once, not per transfer" do
    eth # resolve before counting
    transfers = (1..5).map { |i| raw_transfer("uniqueId" => "0x#{i}:external") }

    selects = count_queries do
      described_class.new.call(wallet: wallet, network: "eth-mainnet", raw_transfers: transfers)
    end.grep(/\A\s*SELECT/i)

    # Dedupe is one prefetch for the whole page (the remaining per-row
    # source_row_hash SELECT is create!'s uniqueness validation), and the
    # type row, security resolution, and price close are memoized across it.
    expect(selects.grep(/SELECT "investment_transactions"\."source_row_hash"/).size).to eq(1)
    # ≤2: find_or_create_by!'s lookup plus its uniqueness validation on
    # first-time creation — constant, where it used to be one per transfer.
    expect(selects.grep(/"transaction_types"/).size).to be <= 2
    expect(selects.grep(/"candles"/).size).to be <= 1
  end

  it "recovers wei-level precision from the raw hex value instead of the JSON float" do
    wei = 10**18 + 1 # 1.000000000000000001 ETH — beyond float precision
    result = described_class.new.call(
      wallet: wallet, network: "eth-mainnet",
      raw_transfers: [ raw_transfer("value" => 1.0,
                                    "rawContract" => { "value" => "0x#{wei.to_s(16)}", "address" => nil, "decimal" => "0x12" }) ]
    )

    expect(result.created).to eq(1)
    expect(InvestmentTransaction.sole.quantity).to eq(BigDecimal("1.000000000000000001"))
  end

  it "downcases addresses so checksummed API output still matches the wallet" do
    result = described_class.new.call(wallet: wallet, network: "eth-mainnet", raw_transfers: [ raw_transfer ])
    expect(result.created).to eq(1)
    expect(InvestmentTransaction.sole.transaction_type.code).to eq("XFER-IN")
  end
end
