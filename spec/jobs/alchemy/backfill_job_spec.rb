require "rails_helper"

RSpec.describe Alchemy::BackfillJob do
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
  let!(:state) do
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                              household_id: wallet.household_id,
                              last_synced_block: 1_000_000, backfill_target_block: 1_000_000)
  end

  before do
    allow(Alchemy::RpcClient).to receive(:new).and_return(client)
    stub_const("Alchemy::BackfillJob::PAGE_PAUSE", 0)
    Candle.create!(security: eth, date: Date.new(2026, 7, 10), close: 2000,
                   currency: "USD", source: "coin_gecko")
    InstrumentQuote.create!(security: eth, price: 2000, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current)
  end

  def raw_transfer(unique_id:, to: wallet.address, from: "0xbbb0000000000000000000000000000000000002")
    {
      "uniqueId"    => unique_id,
      "hash"        => "0x#{unique_id.delete(':')}",
      "blockNum"    => "0x64",
      "from"        => from,
      "to"          => to,
      "value"       => 1.0,
      "asset"       => "ETH",
      "category"    => "external",
      "rawContract" => { "value" => "0x#{(10**18).to_s(16)}", "address" => nil, "decimal" => "0x12" },
      "metadata"    => { "blockTimestamp" => "2026-07-10T12:00:00Z" }
    }
  end

  def page(transfers, page_key: nil)
    Alchemy::RpcClient::TransferPage.new(transfers: transfers, page_key: page_key)
  end

  it "walks both directions from block 0 to the target and completes" do
    expect(client).to receive(:asset_transfers)
      .with(address: wallet.address, direction: :from, from_block: 0, to_block: 1_000_000, page_key: nil)
      .and_return(page([ raw_transfer(unique_id: "0xa:external", from: wallet.address,
                                      to: "0xccc0000000000000000000000000000000000003") ]))
    expect(client).to receive(:asset_transfers)
      .with(address: wallet.address, direction: :to, from_block: 0, to_block: 1_000_000, page_key: nil)
      .and_return(page([ raw_transfer(unique_id: "0xb:external") ]))

    expect {
      described_class.perform_now(wallet.id, "eth-mainnet")
    }.to have_enqueued_job(AlchemySyncJob).and have_enqueued_job(Reconciliation::SweepJob)

    state.reload
    expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Completed)
    expect(state.backfill_cursor).to eq({})
    expect(state.backfill_transfer_count).to eq(2)
    expect(InvestmentTransaction.count).to eq(2)
  end

  it "suppresses workflow events while ingesting history" do
    suppressed = nil
    ingestor   = instance_double(Alchemy::TransferIngestor)
    allow(Alchemy::TransferIngestor).to receive(:new).and_return(ingestor)
    allow(ingestor).to receive(:call) do
      suppressed = Workflows::Events.suppressed?
      Alchemy::TransferIngestor::Result.new(created: 0, duplicates: 0, skipped: Hash.new(0), touched_pairs: Set.new)
    end
    allow(client).to receive(:asset_transfers).and_return(page([]))

    described_class.perform_now(wallet.id, "eth-mainnet")
    expect(suppressed).to be(true)
  end

  it "stops at the page budget, persists the cursor, and self-chains" do
    stub_const("Alchemy::BackfillJob::MAX_PAGES_PER_RUN", 2)
    responses = [
      page([ raw_transfer(unique_id: "0x1:external") ], page_key: "p2"),
      page([ raw_transfer(unique_id: "0x2:external") ], page_key: "p3")
    ]
    allow(client).to receive(:asset_transfers) { responses.shift }

    expect {
      described_class.perform_now(wallet.id, "eth-mainnet")
    }.to have_enqueued_job(described_class).with(wallet.id, "eth-mainnet")

    state.reload
    expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Running)
    expect(state.backfill_cursor).to eq({ "direction" => "from", "page_key" => "p3" })
    expect(state.backfill_transfer_count).to eq(2)
  end

  it "resumes from the persisted cursor" do
    state.update!(backfill_cursor: { "direction" => "to", "page_key" => "p9" },
                  backfill_status: "running")

    expect(client).to receive(:asset_transfers)
      .with(address: wallet.address, direction: :to, from_block: 0, to_block: 1_000_000, page_key: "p9")
      .and_return(page([]))

    described_class.perform_now(wallet.id, "eth-mainnet")
    expect(state.reload.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Completed)
  end

  it "marks the state failed and lets retry_on reschedule on error" do
    allow(client).to receive(:asset_transfers).and_raise(Alchemy::RpcClient::Error, "rate limited")

    expect {
      described_class.perform_now(wallet.id, "eth-mainnet")
    }.to have_enqueued_job(described_class) # retry_on re-enqueues the raised run

    state.reload
    expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Failed)
    expect(state.last_error).to include("rate limited")
  end

  it "is a no-op when the backfill is already completed" do
    state.update!(backfill_status: "completed")
    expect(client).not_to receive(:asset_transfers)

    described_class.perform_now(wallet.id, "eth-mainnet")
  end

  it "pins the target from the chain head when the syncer has not seen the pair" do
    state.update!(backfill_target_block: nil, last_synced_block: nil)
    allow(client).to receive(:block_number).and_return(2_000_012)
    allow(client).to receive(:asset_transfers)
      .with(hash_including(to_block: 2_000_000))
      .and_return(page([]))

    described_class.perform_now(wallet.id, "eth-mainnet")

    state.reload
    expect(state.backfill_target_block).to eq(2_000_000)
    expect(state.last_synced_block).to eq(2_000_000)
    expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Completed)
  end

  it "waits for all networks before finalizing" do
    wallet.update!(networks: %w[eth-mainnet base-mainnet])
    AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "base-mainnet",
                              household_id: wallet.household_id,
                              last_synced_block: 5_000, backfill_target_block: 5_000)
    allow(client).to receive(:asset_transfers).and_return(page([]))

    expect {
      described_class.perform_now(wallet.id, "eth-mainnet")
    }.not_to have_enqueued_job(AlchemySyncJob)
  end
end
