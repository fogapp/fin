require "rails_helper"

RSpec.describe Alchemy::TransferMapper do
  let!(:wallet) { create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001") }
  let(:other_address) { "0xbbb0000000000000000000000000000000000002" }
  let(:eth) do
    Instruments::Resolver.resolve!(instrument_class: "crypto", ticker: "ETH",
                                   name: "Ethereum", security_type: Security::CRYPTO_TYPE)
  end

  before do
    Candle.create!(security: eth, date: Date.new(2026, 7, 10), close: 2000,
                   currency: "USD", source: "coin_gecko")
  end

  def transfer(overrides = {})
    {
      unique_id:        "0xdeadbeef:external",
      hash:             "0xdeadbeef",
      block_num:        1_000_000,
      from:             other_address,
      to:               wallet.address,
      value:            BigDecimal("1.5"),
      asset:            "ETH",
      category:         "external",
      contract_address: nil,
      block_timestamp:  "2026-07-10T12:00:00Z"
    }.merge(overrides)
  end

  def map(overrides = {}, target: wallet, network: "eth-mainnet")
    described_class.call(wallet: target, network: network, transfer: transfer(overrides))
  end

  describe "inbound native transfer" do
    it "creates a Transfer In row priced at the close on the transfer date" do
      result = map
      expect(result.status).to eq(:created)

      txn = result.transaction
      expect(txn.transaction_type.code).to eq("XFER-IN")
      expect(txn.transaction_type.category).to eq("Transfer In")
      expect(txn.security).to eq(eth)
      expect(txn.quantity).to eq(BigDecimal("1.5"))
      expect(txn.price_usd).to eq(2000)
      expect(txn.amount_usd).to eq(3000)
      expect(txn.cost_usd).to eq(3000)
      expect(txn.trade_date).to eq(Date.new(2026, 7, 10))
      expect(txn.source_row_hash).to eq("alchemy_transfer:eth-mainnet:0xdeadbeef:external:in")
      expect(txn.description).to include("Received 1.5 ETH from 0xbbb0…0002")
      expect(txn.account).to eq(wallet.reload.account)
    end

    it "falls back to the latest quote when no candle covers the date" do
      Candle.delete_all
      InstrumentQuote.create!(security: eth, price: 1900, currency: "USD",
                              source: "coin_market_cap", as_of: Time.current)

      result = map
      expect(result.status).to eq(:created)
      expect(result.transaction.price_usd).to eq(1900)
    end
  end

  describe "outbound native transfer" do
    it "creates a Transfer Out row with the direction-suffixed hash" do
      result = map({ from: wallet.address, to: other_address })
      expect(result.status).to eq(:created)

      txn = result.transaction
      expect(txn.transaction_type.code).to eq("XFER-OUT")
      expect(txn.transaction_type.category).to eq("Transfer Out")
      expect(txn.source_row_hash).to end_with(":out")
      expect(txn.description).to include("Sent 1.5 ETH to")
    end
  end

  describe "ledger effects" do
    it "rebuilds the position from transfer rows (in minus out)" do
      map
      map({ unique_id: "0xfeed:external", from: wallet.address, to: other_address, value: BigDecimal("0.4") })

      position = Positions::Rebuild.call(account: wallet.reload.account, security: eth)
      expect(position.quantity).to eq(BigDecimal("1.1"))
      expect(position.cost_basis.to_d).to eq(BigDecimal("2200")) # 3000 in − 800 out
    end
  end

  describe "guards" do
    it "skips unsupported categories" do
      expect(map({ category: "erc721" }).status).to eq(:skipped_category)
    end

    it "skips zero-value contract calls" do
      expect(map({ value: BigDecimal("0") }).status).to eq(:skipped_zero)
      expect(map({ value: nil }).status).to eq(:skipped_zero)
    end

    it "skips self-sends" do
      expect(map({ from: wallet.address, to: wallet.address }).status).to eq(:skipped_self)
    end

    it "skips transfers not touching the wallet" do
      expect(map({ from: other_address, to: "0xccc0000000000000000000000000000000000003" }).status)
        .to eq(:skipped_unrelated)
    end

    it "returns :duplicate for an already-ingested transfer" do
      expect(map.status).to eq(:created)
      expect(map.status).to eq(:duplicate)
      expect(InvestmentTransaction.count).to eq(1)
    end

    it "skips transfers with an unparseable timestamp" do
      expect(map({ block_timestamp: nil }).status).to eq(:skipped_malformed)
    end

    it "skips unpriceable tokens" do
      Candle.delete_all
      expect(map.status).to eq(:skipped_unpriced)
    end

    it "falls back to the latest observed snapshot price when no provider prices the token" do
      Candle.delete_all
      PositionSnapshot.create!(household_id: wallet.household_id, account_id: wallet.ensure_account!.id,
                               security: eth, as_of_date: Date.current, quantity: 2, price: 1750,
                               market_value: 3500, source_row_hash: "alchemy_wallet:#{wallet.id}:#{eth.id}")

      result = map
      expect(result.status).to eq(:created)
      expect(result.transaction.price_usd).to eq(1750)
    end
  end

  describe "erc20 transfers" do
    let(:usdc_contract) { "0xcccc000000000000000000000000000000000004" }
    let(:usdc) do
      Instruments::Resolver.resolve!(instrument_class: "crypto", ticker: "USDC",
                                     name: "USD Coin", security_type: Security::CRYPTO_TYPE)
    end

    def usdc_transfer(overrides = {})
      transfer({ unique_id: "0xbead:log:3", category: "erc20", asset: "USDC",
                 contract_address: usdc_contract, value: BigDecimal("250") }.merge(overrides))
    end

    before do
      Candle.create!(security: usdc, date: Date.new(2026, 7, 10), close: 1,
                     currency: "USD", source: "coin_gecko")
    end

    it "skips tokens whose contract the balance sync has never priced" do
      result = described_class.call(wallet: wallet, network: "eth-mainnet", transfer: usdc_transfer)
      expect(result.status).to eq(:skipped_unknown_token)
    end

    it "ingests transfers from allowlisted contracts" do
      wallet.update!(known_token_contracts: { "eth-mainnet" => [ usdc_contract ] })

      result = described_class.call(wallet: wallet, network: "eth-mainnet", transfer: usdc_transfer)
      expect(result.status).to eq(:created)
      expect(result.transaction.security).to eq(usdc)
      expect(result.transaction.amount_usd).to eq(250)
    end
  end

  describe "self-transfer linking between household wallets" do
    let!(:other_wallet) { create(:alchemy_wallet, address: other_address) }

    def out_leg = map({ from: wallet.address, to: other_address }, target: wallet)
    def in_leg  = map({ from: wallet.address, to: other_address }, target: other_wallet)

    it "links both legs with a confirmed transfer (out leg first)" do
      out_txn = out_leg.transaction
      in_txn  = in_leg.transaction

      transfer = Transfer.sole
      expect(transfer.from_transaction).to eq(out_txn)
      expect(transfer.to_transaction).to eq(in_txn)
      expect(transfer.confirmed?).to be(true)
      expect(transfer.confirmation_source).to eq(Transfer::ConfirmationSource::Auto)
      expect(out_txn.reload.transfer_id).to eq(transfer.id)
      expect(in_txn.reload.transfer_id).to eq(transfer.id)
    end

    it "links both legs regardless of processing order (in leg first)" do
      in_txn  = in_leg.transaction
      out_txn = out_leg.transaction

      transfer = Transfer.sole
      expect(transfer.from_transaction).to eq(out_txn)
      expect(transfer.to_transaction).to eq(in_txn)
      expect(transfer.confirmed?).to be(true)
    end

    it "does not link when the counterparty is not a household wallet" do
      map({ from: wallet.address, to: "0xddd0000000000000000000000000000000000005" })
      expect(Transfer.count).to eq(0)
    end
  end
end
