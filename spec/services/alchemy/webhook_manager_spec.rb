require "rails_helper"

RSpec.describe Alchemy::WebhookManager do
  let!(:config) do
    create(:alchemy_configuration,
           transactions_enabled: true, sync_frequency: "realtime",
           auth_token: "notify-token", webhook_base_url: "https://fin.example.com")
  end
  let!(:wallet) do
    create(:alchemy_wallet, address: "0xaaa0000000000000000000000000000000000001",
                            networks: [ "eth-mainnet" ])
  end
  let(:client) { instance_double(Alchemy::NotifyClient) }

  before { allow(Alchemy::NotifyClient).to receive(:new).and_return(client) }

  it "creates a webhook per network with all active wallet addresses" do
    expect(client).to receive(:create_address_activity_webhook)
      .with(network: "eth-mainnet", url: "https://fin.example.com/webhooks/alchemy",
            addresses: [ wallet.address ])
      .and_return({ external_id: "wh_new", signing_key: "whsec_abc" })

    described_class.new.sync!

    webhook = AlchemyWebhook.sole
    expect(webhook.network).to eq("eth-mainnet")
    expect(webhook.external_id).to eq("wh_new")
    expect(webhook.signing_key).to eq("whsec_abc")
    expect(webhook.status).to eq(AlchemyWebhook::Status::Active)
  end

  it "diffs addresses on an existing webhook" do
    AlchemyWebhook.create!(household_id: Current.household.id, network: "eth-mainnet",
                           external_id: "wh_1", signing_key: "k", url: "https://fin.example.com/webhooks/alchemy")
    stale = "0xbbb0000000000000000000000000000000000002"
    allow(client).to receive(:team_webhooks)
      .and_return([ { "id" => "wh_1", "addresses" => [ stale ] } ])

    expect(client).to receive(:update_webhook_addresses)
      .with(external_id: "wh_1", add: [ wallet.address ], remove: [ stale ])

    described_class.new.sync!
    expect(AlchemyWebhook.sole.status).to eq(AlchemyWebhook::Status::Active)
  end

  # After a move (or an edited base URL) the registered webhook still
  # delivers to the old address; Alchemy can't retarget one, so it's replaced.
  it "replaces a webhook registered for a different URL" do
    AlchemyWebhook.create!(household_id: Current.household.id, network: "eth-mainnet",
                           external_id: "wh_old", signing_key: "k", url: "https://old.example.com/webhooks/alchemy")

    expect(client).to receive(:delete_webhook).with(external_id: "wh_old").ordered
    expect(client).to receive(:create_address_activity_webhook)
      .with(network: "eth-mainnet", url: "https://fin.example.com/webhooks/alchemy", addresses: [ wallet.address ])
      .ordered.and_return({ external_id: "wh_new", signing_key: "whsec_new" })

    described_class.new.sync!

    expect(AlchemyWebhook.sole).to have_attributes(
      external_id: "wh_new", url: "https://fin.example.com/webhooks/alchemy"
    )
  end

  it "tears down webhooks when realtime is turned off" do
    config.update!(sync_frequency: "daily")
    AlchemyWebhook.create!(household_id: Current.household.id, network: "eth-mainnet",
                           external_id: "wh_1", signing_key: "k", url: "https://x/webhooks/alchemy")

    expect(client).to receive(:delete_webhook).with(external_id: "wh_1")

    described_class.new.sync!
    expect(AlchemyWebhook.count).to eq(0)
  end

  it "tears down webhooks for networks no longer used by any wallet" do
    AlchemyWebhook.create!(household_id: Current.household.id, network: "base-mainnet",
                           external_id: "wh_base", signing_key: "k", url: "https://x/webhooks/alchemy")
    allow(client).to receive(:team_webhooks).and_return([])
    expect(client).to receive(:delete_webhook).with(external_id: "wh_base")
    expect(client).to receive(:create_address_activity_webhook)
      .and_return({ external_id: "wh_eth", signing_key: "s" })

    described_class.new.sync!
    expect(AlchemyWebhook.pluck(:network)).to eq([ "eth-mainnet" ])
  end

  it "is a no-op without auth token or base URL" do
    config.update!(auth_token: nil)
    expect(Alchemy::NotifyClient).not_to receive(:new)

    expect(described_class.new.sync!).to eq([])
    expect(AlchemyWebhook.count).to eq(0)
  end

  it "marks the row errored and continues when the API fails" do
    expect(client).to receive(:create_address_activity_webhook)
      .and_raise(Alchemy::NotifyClient::Error, "Alchemy Notify 401: bad token")

    expect { described_class.new.sync! }.not_to raise_error
    expect(AlchemyWebhook.count).to eq(0) # creation failed → no row
  end

  it "records the error on an existing row when the address diff fails" do
    AlchemyWebhook.create!(household_id: Current.household.id, network: "eth-mainnet",
                           external_id: "wh_1", signing_key: "k", url: "https://fin.example.com/webhooks/alchemy")
    allow(client).to receive(:team_webhooks).and_return([])
    allow(client).to receive(:update_webhook_addresses)
      .and_raise(Alchemy::NotifyClient::Error, "Alchemy Notify 500: nope")

    described_class.new.sync!

    webhook = AlchemyWebhook.sole
    expect(webhook.status).to eq(AlchemyWebhook::Status::Error)
    expect(webhook.last_error).to include("500")
  end
end
