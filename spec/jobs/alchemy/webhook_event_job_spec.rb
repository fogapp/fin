require "rails_helper"

RSpec.describe Alchemy::WebhookEventJob do
  let!(:config) { create(:alchemy_configuration, transactions_enabled: true, sync_frequency: "realtime") }
  let!(:wallet) { create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001") }
  let!(:webhook) do
    AlchemyWebhook.create!(household_id: Current.household.id, network: "eth-mainnet",
                           external_id: "wh_123", signing_key: "k", url: "https://x/webhooks/alchemy")
  end

  def payload(addresses)
    { "event" => { "network" => "ETH_MAINNET",
                   "activity" => addresses.map { |a| { "fromAddress" => a, "toAddress" => "0xother" } } } }
  end

  it "enqueues a targeted sync for wallets named in the activity (case-insensitive)" do
    expect {
      described_class.perform_now(webhook.id, payload([ wallet.address.upcase ]))
    }.to have_enqueued_job(Alchemy::TransactionSyncJob).with(Current.household.id, wallet_ids: [ wallet.id ])
  end

  it "does nothing when no household wallet is involved" do
    expect {
      described_class.perform_now(webhook.id, payload([ "0xbbb0000000000000000000000000000000000002" ]))
    }.not_to have_enqueued_job(Alchemy::TransactionSyncJob)
  end

  it "does nothing when transaction sync is disabled" do
    config.update!(transactions_enabled: false)
    expect {
      described_class.perform_now(webhook.id, payload([ wallet.address ]))
    }.not_to have_enqueued_job(Alchemy::TransactionSyncJob)
  end
end
