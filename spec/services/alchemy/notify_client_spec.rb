require "rails_helper"

RSpec.describe Alchemy::NotifyClient do
  before { create(:alchemy_configuration, auth_token: "notify-token") }

  it "creates an address activity webhook and returns id + signing key" do
    stub = stub_request(:post, "https://dashboard.alchemy.com/api/create-webhook")
      .with(headers: { "X-Alchemy-Token" => "notify-token" },
            body: hash_including("network" => "ETH_MAINNET", "webhook_type" => "ADDRESS_ACTIVITY"))
      .to_return(status: 200, body: { "data" => { "id" => "wh_1", "signing_key" => "whsec" } }.to_json)

    result = described_class.new.create_address_activity_webhook(
      network: "eth-mainnet", url: "https://x/webhooks/alchemy", addresses: [ "0xabc" ]
    )
    expect(stub).to have_been_requested
    expect(result).to eq(external_id: "wh_1", signing_key: "whsec")
  end

  it "patches address diffs and skips the call when the diff is empty" do
    stub = stub_request(:patch, "https://dashboard.alchemy.com/api/update-webhook-addresses")
      .with(body: hash_including("webhook_id" => "wh_1", "addresses_to_add" => [ "0xnew" ]))
      .to_return(status: 200, body: "{}")

    client = described_class.new
    client.update_webhook_addresses(external_id: "wh_1", add: [ "0xnew" ])
    client.update_webhook_addresses(external_id: "wh_1") # empty diff → no request
    expect(stub).to have_been_requested.once
  end

  it "tolerates deleting a webhook that is already gone" do
    stub_request(:delete, "https://dashboard.alchemy.com/api/delete-webhook")
      .to_return(status: 404, body: { "message" => "not found" }.to_json)

    expect { described_class.new.delete_webhook(external_id: "wh_gone") }.not_to raise_error
  end

  it "raises with the API message on other failures" do
    stub_request(:get, "https://dashboard.alchemy.com/api/team-webhooks")
      .to_return(status: 401, body: { "message" => "unauthorized" }.to_json)

    expect { described_class.new.team_webhooks }
      .to raise_error(Alchemy::NotifyClient::Error, /401.*unauthorized/)
  end

  it "requires an auth token" do
    AlchemyConfiguration.current.update!(auth_token: nil)
    expect { described_class.new }.to raise_error(ArgumentError, /auth token/)
  end
end
