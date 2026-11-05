require "rails_helper"

RSpec.describe "Alchemy inbound webhooks", type: :request do
  include ActiveJob::TestHelper

  let!(:webhook) do
    AlchemyWebhook.create!(
      household_id: Current.household.id,
      network: "eth-mainnet",
      external_id: "wh_123",
      signing_key: "whsec_test",
      url: "https://fin.example.com/webhooks/alchemy"
    )
  end

  def payload(webhook_id: "wh_123")
    {
      "webhookId" => webhook_id,
      "id"        => "whevt_1",
      "createdAt" => "2026-07-15T00:00:00Z",
      "type"      => "ADDRESS_ACTIVITY",
      "event"     => {
        "network"  => "ETH_MAINNET",
        "activity" => [ { "fromAddress" => "0xabc", "toAddress" => "0xdef", "category" => "external" } ]
      }
    }.to_json
  end

  def signature_for(body, key: "whsec_test")
    OpenSSL::HMAC.hexdigest("SHA256", key, body)
  end

  it "accepts a validly signed delivery and enqueues the hint job with a delay" do
    body = payload

    freeze_time do
      post "/webhooks/alchemy", params: body,
           headers: { "Content-Type" => "application/json", "X-Alchemy-Signature" => signature_for(body) }

      expect(response).to have_http_status(:ok)
      expect(Alchemy::WebhookEventJob).to have_been_enqueued.at(90.seconds.from_now)
    end
    expect(webhook.reload.last_received_at).to be_present
  end

  it "rejects a bad signature with 401 and records an activity warning" do
    body = payload

    post "/webhooks/alchemy", params: body,
         headers: { "Content-Type" => "application/json", "X-Alchemy-Signature" => signature_for(body, key: "wrong") }

    expect(response).to have_http_status(:unauthorized)
    expect(Alchemy::WebhookEventJob).not_to have_been_enqueued
    entry = ActivityEntry.order(:created_at).last
    expect(entry.event).to eq("webhook.rejected")
  end

  it "rejects a missing signature" do
    post "/webhooks/alchemy", params: payload, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "404s an unknown webhook id" do
    body = payload(webhook_id: "wh_other")
    post "/webhooks/alchemy", params: body,
         headers: { "Content-Type" => "application/json", "X-Alchemy-Signature" => signature_for(body) }

    expect(response).to have_http_status(:not_found)
  end

  it "400s malformed payloads" do
    post "/webhooks/alchemy", params: "not json", headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:bad_request)
  end
end
