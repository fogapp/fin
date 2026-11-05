# typed: false
# frozen_string_literal: true

require "rails_helper"

# fog-integration/1 with consent: fog asks, a household admin answers at
# /connect/<ticket>, fog claims the read-only token once.
RSpec.describe "fog-integration/1 surface", type: :request do
  let(:token) { "fog-test-token" }

  around do |example|
    previous = ENV["FOG_API_TOKEN"]
    ENV["FOG_API_TOKEN"] = token
    example.run
  ensure
    ENV["FOG_API_TOKEN"] = previous
  end

  def fog_headers = { "Authorization" => "Bearer #{token}" }
  def bearer(value) = { "Authorization" => "Bearer #{value}" }
  def json = JSON.parse(response.body)

  # household_context signs an admin in to the first household.
  let(:admin) { Current.user }
  let(:admin_headers) { bearer(create(:api_token).raw_token) }
  let(:return_to) { "https://fog.example/api/integrations/return?state=one-time" }

  def ask(consumer: "newtab", offer: "finance", return_to: self.return_to)
    post "/fog/integrations", params: { consumer: consumer, offer: offer, return_to: return_to }.compact,
      headers: fog_headers, as: :json
  end

  # Mint and read back the id and the ticket from the consent path.
  def asked!
    ask
    expect(response).to have_http_status(:accepted)
    [ json["id"], json["consent"].delete_prefix("/connect/") ]
  end

  def approve!(ticket)
    post "/api/v1/fog_connections/#{ticket}/approve", headers: admin_headers
    expect(response).to have_http_status(:ok)
    json["return_to"]
  end

  def claim(id) = post("/fog/integrations/#{id}/claim", params: {}, headers: fog_headers, as: :json)

  it "rejects a wrong bearer everywhere" do
    post "/fog/integrations", params: { consumer: "newtab", offer: "finance", return_to: return_to }, headers: bearer("nope"), as: :json
    expect(response).to have_http_status(:unauthorized)
    get "/fog/integrations/#{SecureRandom.uuid}", headers: bearer("nope")
    expect(response).to have_http_status(:unauthorized)
    post "/fog/integrations/#{SecureRandom.uuid}/claim", headers: bearer("nope")
    expect(response).to have_http_status(:unauthorized)
  end

  describe "the ask" do
    it "records a pending request and answers the page to approve it on" do
      id, ticket = asked!

      expect(id).to match(FogIntegrations::UUID)
      expect(ticket.length).to be >= 32
      row = FogIntegration.unscoped.find(id)
      expect(row).to be_pending
      expect(row.consumer).to eq("newtab")
      expect(row.household).to eq(Current.household)
      expect(row.expires_at).to be_within(1.minute).of(30.minutes.from_now)
      expect(row.ticket_digest).to eq(Digest::SHA256.hexdigest(ticket))
      expect(row.api_token).to be_nil
    end

    it "needs a return_to, because a person has to approve it" do
      ask(return_to: nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("approval").and include("return_to")
      expect(FogIntegration.unscoped.count).to eq(0)
    end

    it "refuses a return_to that is not an address" do
      ask(return_to: "javascript:alert(1)")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("http")
    end

    it "refuses an offer it does not make, and a consumer that is not an app name" do
      ask(offer: "everything")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("finance")

      ask(consumer: "Not An App")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("app name")
    end

    it "says to finish setup before there is a household" do
      Current.reset
      HouseholdMembership.delete_all
      Household.delete_all
      ask
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].first).to include("setup")
    end
  end

  describe "the consent page's API" do
    it "shows a household admin what is asked" do
      _id, ticket = asked!
      get "/api/v1/fog_connections/#{ticket}", headers: admin_headers

      expect(response).to have_http_status(:ok)
      expect(json).to include("consumer" => "newtab", "state" => "pending")
      expect(json["offer"]).to include("id" => "finance", "title" => "Finances")
      expect(json["offer"]["blurb"]).to include("change nothing")
      expect(json["expires_at"]).to be_present
    end

    it "is for household admins only" do
      _id, ticket = asked!
      member = create(:user)
      create(:household_membership, user: member, household: Current.household, role: "member")
      headers = bearer(create(:api_token, user: member).raw_token)

      get "/api/v1/fog_connections/#{ticket}", headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to include("household admin")
      post "/api/v1/fog_connections/#{ticket}/approve", headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(ApiToken.unscoped.where(name: "fog: newtab")).not_to exist
    end

    it "answers 404 for a ticket it never issued, or one from another household" do
      get "/api/v1/fog_connections/nope", headers: admin_headers
      expect(response).to have_http_status(:not_found)

      _id, ticket = asked!
      other = create(:household)
      create(:household_membership, user: admin, household: other, role: "admin")
      get "/api/v1/fog_connections/#{ticket}", headers: bearer(create(:api_token, household: other).raw_token)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "approval" do
    it "mints a read-only token in the approver's name, held for fog, and sends the person back approved" do
      id, ticket = asked!
      back = approve!(ticket)

      expect(back).to eq("https://fog.example/api/integrations/return?state=one-time&result=approved")
      expect(json["state"]).to eq("approved")
      row = FogIntegration.unscoped.find(id)
      expect(row.state).to eq(FogIntegration::State::Approved)
      expect(row.approved_by).to eq(admin)
      expect(row.secret).to be_present
      minted = row.api_token
      expect(minted.name).to eq("fog: newtab")
      expect(minted.user).to eq(admin)
      expect(minted.household).to eq(Current.household)
      expect(minted).to be_read_only
      expect(ApiToken.authenticate(row.secret)).to eq(minted)
      # Encrypted at rest.
      raw = ActiveRecord::Base.connection.select_value("SELECT secret FROM fog_integrations WHERE id = '#{id}'")
      expect(raw).not_to include(row.secret)

      get "/api/v1/fog_connections/#{ticket}", headers: admin_headers
      expect(json["state"]).to eq("approved")
    end

    it "cannot be answered twice" do
      _id, ticket = asked!
      approve!(ticket)
      post "/api/v1/fog_connections/#{ticket}/approve", headers: admin_headers
      expect(response).to have_http_status(:conflict)
      post "/api/v1/fog_connections/#{ticket}/decline", headers: admin_headers
      expect(response).to have_http_status(:conflict)
      expect(ApiToken.unscoped.where(name: "fog: newtab").count).to eq(1)
    end
  end

  describe "the claim" do
    it "answers 409 while nobody has approved" do
      id, _ticket = asked!
      claim(id)
      expect(response).to have_http_status(:conflict)
      expect(json["errors"]).to eq([ "Nobody has approved this in Fin yet." ])
    end

    it "hands over the token once, which reads Fin and changes nothing" do
      id, ticket = asked!
      approve!(ticket)

      claim(id)
      expect(response).to have_http_status(:ok)
      secret = json.dig("secrets", "FIN_API_TOKEN")
      expect(secret).to be_present
      expect(json["secrets"].keys).to eq([ "FIN_API_TOKEN" ])
      row = FogIntegration.unscoped.find(id)
      expect(row).to be_claimed
      expect(row.secret).to be_nil
      expect(row.claimed_at).to be_present

      get "/api/v1/net_worth", headers: bearer(secret)
      expect(response).to have_http_status(:ok)
      get "/api/v1/subscriptions/upcoming", headers: bearer(secret)
      expect(response).to have_http_status(:ok)
      post "/api/v1/api_tokens", params: { name: "escalate" }, headers: bearer(secret), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("This token can only read Fin, not change it.")

      claim(id)
      expect(response).to have_http_status(:gone)
      expect(json["errors"].first).to include("already claimed")
    end

    it "answers 404 for an integration it never made" do
      claim(SecureRandom.uuid)
      expect(response).to have_http_status(:not_found)
      claim("garbage")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "status and revocation" do
    it "is active once claimed, tracks the token's use, and is revoked with it" do
      id, ticket = asked!
      get "/fog/integrations/#{id}", headers: fog_headers
      expect(response).to have_http_status(:ok)
      expect(json).to include("id" => id, "active" => false, "last_activity_at" => nil)
      expect(json["created_at"]).to be_present

      approve!(ticket)
      get "/fog/integrations/#{id}", headers: fog_headers
      expect(json["active"]).to be(false)

      claim(id)
      secret = json.dig("secrets", "FIN_API_TOKEN")
      get "/fog/integrations/#{id}", headers: fog_headers
      expect(json).to include("active" => true, "last_activity_at" => nil)

      get "/api/v1/me", headers: bearer(secret)
      get "/fog/integrations/#{id}", headers: fog_headers
      expect(json["last_activity_at"]).to be_present

      delete "/fog/integrations/#{id}", headers: fog_headers
      expect(response).to have_http_status(:no_content)
      expect(ApiToken.authenticate(secret)).to be_nil
      expect(FogIntegration.unscoped.exists?(id)).to be(false)

      get "/fog/integrations/#{id}", headers: fog_headers
      expect(response).to have_http_status(:not_found)
      delete "/fog/integrations/#{id}", headers: fog_headers
      expect(response).to have_http_status(:not_found)
    end

    it "reads as inactive once the approver revokes the token from their list" do
      id, ticket = asked!
      approve!(ticket)
      claim(id)
      delete "/api/v1/api_tokens/#{FogIntegration.unscoped.find(id).api_token_id}", headers: admin_headers
      expect(response).to have_http_status(:no_content)

      get "/fog/integrations/#{id}", headers: fog_headers
      expect(json["active"]).to be(false)
    end

    it "deletes a pending request too, which is how fog cancels one" do
      id, _ticket = asked!
      delete "/fog/integrations/#{id}", headers: fog_headers
      expect(response).to have_http_status(:no_content)
      expect(FogIntegration.unscoped.exists?(id)).to be(false)
    end
  end

  describe "a decline" do
    it "sends the person back declined, mints nothing, and refuses the claim" do
      id, ticket = asked!
      post "/api/v1/fog_connections/#{ticket}/decline", headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(json).to eq("state" => "declined",
        "return_to" => "https://fog.example/api/integrations/return?state=one-time&result=declined")
      expect(ApiToken.unscoped.where(name: "fog: newtab")).not_to exist

      claim(id)
      expect(response).to have_http_status(:conflict)
      expect(json["errors"].first).to include("declined")
      get "/fog/integrations/#{id}", headers: fog_headers
      expect(json["active"]).to be(false)
      get "/api/v1/fog_connections/#{ticket}", headers: admin_headers
      expect(json["state"]).to eq("declined")
    end
  end

  describe "an expired ticket" do
    it "can no longer be answered or claimed" do
      id, ticket = asked!
      travel 31.minutes do
        get "/api/v1/fog_connections/#{ticket}", headers: admin_headers
        expect(response).to have_http_status(:ok)
        expect(json["state"]).to eq("expired")

        post "/api/v1/fog_connections/#{ticket}/approve", headers: admin_headers
        expect(response).to have_http_status(:gone)
        expect(json["error"]).to include("expired")
        expect(ApiToken.unscoped.where(name: "fog: newtab")).not_to exist

        claim(id)
        expect(response).to have_http_status(:gone)
        expect(json["errors"].first).to include("expired")
      end
    end

    it "does not expire an answer once given" do
      id, ticket = asked!
      approve!(ticket)
      travel 31.minutes do
        claim(id)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
