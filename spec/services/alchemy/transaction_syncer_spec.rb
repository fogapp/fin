require "rails_helper"

RSpec.describe Alchemy::TransactionSyncer do
  include ActiveJob::TestHelper

  let!(:config) { create(:alchemy_configuration) }
  let!(:wallet) do
    create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001",
                            networks: [ "eth-mainnet" ])
  end
  let(:client) { instance_double(Alchemy::RpcClient) }
  let(:eth) do
    Instruments::Resolver.resolve!(instrument_class: "crypto", ticker: "ETH",
                                   name: "Ethereum", security_type: Security::CRYPTO_TYPE)
  end

  before do
    allow(Alchemy::RpcClient).to receive(:new).and_return(client)
    Candle.create!(security: eth, date: Date.new(2026, 7, 10), close: 2000,
                   currency: "USD", source: "coin_gecko")
  end

  def raw_transfer(unique_id: "0xdead:external", to: wallet.address, from: "0xbbb0000000000000000000000000000000000002")
    {
      "uniqueId"    => unique_id,
      "hash"        => "0xdead",
      "blockNum"    => "0xf4240",
      "from"        => from,
      "to"          => to,
      "value"       => 1.5,
      "asset"       => "ETH",
      "category"    => "external",
      "rawContract" => { "value" => "0x#{(15 * 10**17).to_s(16)}", "address" => nil, "decimal" => "0x12" },
      "metadata"    => { "blockTimestamp" => "2026-07-10T12:00:00Z" }
    }
  end

  def empty_page
    Alchemy::RpcClient::TransferPage.new(transfers: [], page_key: nil)
  end

  it "pins the cursor to the safe head on first sight and enqueues a backfill" do
    allow(client).to receive(:block_number).and_return(1_000_012)

    expect {
      described_class.new.call
    }.to have_enqueued_job(Alchemy::BackfillJob).with(wallet.id, "eth-mainnet")

    state = AlchemyWalletSync.find_by!(alchemy_wallet: wallet, network: "eth-mainnet")
    expect(state.last_synced_block).to eq(1_000_000) # head − 12 confirmations
    expect(state.backfill_target_block).to eq(1_000_000)
    expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Pending)
    expect(client).not_to have_received(:asset_transfers) if client.respond_to?(:asset_transfers)
  end

  it "fetches both directions over the cursor gap and advances the cursor" do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id, last_synced_block: 999_000)
    allow(client).to receive(:block_number).and_return(1_000_012)

    expect(client).to receive(:asset_transfers)
      .with(address: wallet.address, direction: :from, from_block: 999_001, to_block: 1_000_000, page_key: nil)
      .and_return(empty_page)
    expect(client).to receive(:asset_transfers)
      .with(address: wallet.address, direction: :to, from_block: 999_001, to_block: 1_000_000, page_key: nil)
      .and_return(Alchemy::RpcClient::TransferPage.new(transfers: [ raw_transfer ], page_key: nil))

    result = described_class.new.call
    expect(result.errors).to eq([]); expect(result.new_transfers).to eq(1)
    expect(InvestmentTransaction.sole.transaction_type.code).to eq("XFER-IN")

    state = AlchemyWalletSync.find_by!(alchemy_wallet: wallet, network: "eth-mainnet")
    expect(state.last_synced_block).to eq(1_000_000)
    expect(state.last_error).to be_nil
  end

  it "does nothing when the safe head has not advanced past the cursor" do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id, last_synced_block: 1_000_000)
    allow(client).to receive(:block_number).and_return(1_000_005) # safe head 999,993 < cursor

    result = described_class.new.call
    expect(result.new_transfers).to eq(0)
    expect(AlchemyWalletSync.sole.last_synced_block).to eq(1_000_000)
  end

  it "follows pageKey pagination within a direction" do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id, last_synced_block: 999_000)
    allow(client).to receive(:block_number).and_return(1_000_012)

    allow(client).to receive(:asset_transfers).with(hash_including(direction: :from, page_key: nil))
      .and_return(Alchemy::RpcClient::TransferPage.new(transfers: [ raw_transfer ], page_key: "p2"))
    allow(client).to receive(:asset_transfers).with(hash_including(direction: :from, page_key: "p2"))
      .and_return(Alchemy::RpcClient::TransferPage.new(
        transfers: [ raw_transfer(unique_id: "0xbeef:external") ], page_key: nil
      ))
    allow(client).to receive(:asset_transfers).with(hash_including(direction: :to))
      .and_return(empty_page)

    result = described_class.new.call
    expect(result.new_transfers).to eq(2)
  end

  it "keeps the cursor and records the error when ingest fails" do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id, last_synced_block: 999_000)
    allow(client).to receive(:block_number).and_return(1_000_012)
    allow(client).to receive(:asset_transfers).and_raise(Alchemy::RpcClient::Error, "boom")

    result = described_class.new.call
    expect(result.errors.size).to eq(1)

    state = AlchemyWalletSync.sole
    expect(state.last_synced_block).to eq(999_000) # not advanced
    expect(state.last_error).to include("boom")
  end
end
