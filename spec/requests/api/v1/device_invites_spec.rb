require "rails_helper"

RSpec.describe "Api::V1::DeviceInvites", type: :request do
  let(:user)         { create(:user, email: "owner@example.com", name: "Owner") }
  let(:token)        { create(:api_token, user: user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/device_invites" do
    it "returns 401 without authentication" do
      post "/api/v1/device_invites"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 201 with a token and an expiry the Devices panel renders" do
      post "/api/v1/device_invites", headers: auth_headers

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body["expires_at"]).to be_present
      expect(Time.zone.parse(body["expires_at"])).to be_within(1.minute).of(15.minutes.from_now)
    end

    it "signs a token that carries the current user's identity" do
      post "/api/v1/device_invites", headers: auth_headers

      payload = Rails.application.message_verifier(:device_invite)
                     .verify(response.parsed_body["token"])

      expect(payload).to include(
        "intent"  => "device_invite",
        "user_id" => user.id,
        "email"   => "owner@example.com",
        "name"    => "Owner"
      )
    end

    it "leaves a plain invite unbound to any address" do
      post "/api/v1/device_invites", headers: auth_headers

      expect(response.parsed_body).to include("host" => nil, "url" => nil)
    end

    it "issues a token that stops verifying once it has expired" do
      post "/api/v1/device_invites", headers: auth_headers
      invite_token = response.parsed_body["token"]

      travel 16.minutes do
        expect {
          Rails.application.message_verifier(:device_invite).verify(invite_token)
        }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
      end
    end
  end

  # The instance is moving: passkeys stay bound to this address, so each
  # member carries a link that works only at the new one.
  describe "POST /api/v1/device_invites with an address" do
    let(:household) { Current.household }

    def payload_of(response)
      Rails.application.message_verifier(:device_invite).verify(response.parsed_body["token"])
    end

    before { create(:household_membership, user: user, household: household, role: "admin") }

    it "issues a week-long link bound to the new host, as a ready-to-open URL" do
      post "/api/v1/device_invites", params: { address: "Fin.NewHome.example" }, headers: auth_headers

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["host"]).to eq("fin.newhome.example")
      expect(body["url"]).to start_with("https://fin.newhome.example/join-device?token=")
      expect(Time.zone.parse(body["expires_at"])).to be_within(1.minute).of(7.days.from_now)
      expect(payload_of(response)).to include("user_id" => user.id, "host" => "fin.newhome.example")
    end

    it "keeps an explicit scheme and port in the URL but binds to the bare host" do
      post "/api/v1/device_invites", params: { address: "http://192.168.1.50:3001/settings" }, headers: auth_headers

      expect(response.parsed_body["url"]).to start_with("http://192.168.1.50:3001/join-device?token=")
      expect(response.parsed_body["host"]).to eq("192.168.1.50")
    end

    it "rejects an address that isn't a host" do
      post "/api/v1/device_invites", params: { address: "not a host" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets an admin issue one for another member of the household" do
      member = create(:user, email: "spouse@example.com")
      create(:household_membership, user: member, household: household, role: "member")

      post "/api/v1/device_invites", params: { address: "fin.newhome.example", user_id: member.id }, headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(payload_of(response)).to include("user_id" => member.id, "email" => "spouse@example.com")
    end

    it "refuses a non-admin issuing for someone else" do
      member = create(:user)
      create(:household_membership, user: member, household: household, role: "member")
      member_token = create(:api_token, user: member, household: household)

      post "/api/v1/device_invites", params: { address: "fin.newhome.example", user_id: user.id },
                                     headers: { "Authorization" => "Bearer #{member_token.raw_token}" }

      expect(response).to have_http_status(:forbidden)
    end

    it "never reaches a user outside the household" do
      outsider = create(:user)
      create(:household_membership, user: outsider, household: create(:household))

      post "/api/v1/device_invites", params: { address: "fin.newhome.example", user_id: outsider.id }, headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end

    it "won't issue a same-address invite for another member" do
      member = create(:user)
      create(:household_membership, user: member, household: household, role: "member")

      post "/api/v1/device_invites", params: { user_id: member.id }, headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
