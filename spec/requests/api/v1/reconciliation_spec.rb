require "rails_helper"

RSpec.describe "Api::V1::Reconciliation", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)  { create(:account) }
  let(:security) { create(:security, ticker: "AAPL") }

  def observe!(qty)
    create(:position_snapshot, account: account, security: security, as_of_date: Date.current,
           quantity: qty, source_row_hash: "plaid_holding:#{account.id}:#{security.id}:#{Date.current}")
  end

  describe "POST /reconciliation/accept" do
    it "accepts the custodian balance for a drift finding key" do
      observe!(25)

      post "/api/v1/reconciliation/accept",
           params: { key: "reconciliation:#{account.id}:#{security.id}" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "adjusted", "delta" => 25.0)
      expect(Position.sole.quantity).to eq(25)
    end
  end

  describe "POST /reconciliation/accept_all" do
    it "queues the bulk acceptance" do
      expect {
        post "/api/v1/reconciliation/accept_all", headers: auth_headers
      }.to have_enqueued_job(Reconciliation::AcceptAllJob)
      expect(response.parsed_body["status"]).to eq("queued")
    end
  end

  describe "POST /issues/dismiss_all" do
    it "dismisses all active issues, optionally by source" do
      Issue.raise_once!(key: "a", title: "A", source: "system_audit")
      Issue.raise_once!(key: "b", title: "B", source: "reconciliation")

      post "/api/v1/issues/dismiss_all", params: { source: "system_audit" },
           headers: auth_headers, as: :json
      expect(response.parsed_body["dismissed"]).to eq(1)
      expect(Issue.active.count).to eq(1)

      post "/api/v1/issues/dismiss_all", headers: auth_headers
      expect(response.parsed_body["dismissed"]).to eq(1)
      expect(Issue.active.count).to eq(0)
    end
  end
end
