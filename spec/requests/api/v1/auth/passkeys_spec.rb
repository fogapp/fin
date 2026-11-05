require "rails_helper"
# The gem is `require: false` in the Gemfile and normally loaded by the
# controllers' before_action, but FakeClient touches WebAuthn.configuration
# at construction — which some examples do before their first request.
require "webauthn"
require "webauthn/fake_client"

RSpec.describe "Passkey auth", type: :request do
  # The relying party is derived from the request, so the fake client must
  # present the origin Rack::Test requests actually come from.
  let(:origin)     { "http://www.example.com" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  describe "POST /api/v1/auth/passkey/register/begin" do
    it "returns creation options and a signed challenge token for a new user" do
      post "/api/v1/auth/passkey/register/begin", params: { email: "new@example.com", name: "New" }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("options", "challenge")).to be_present
      expect(body["challenge_token"]).to be_present
    end

    it "refuses first-passkey enrollment on an existing account without an invite" do
      # Knowing an email must not be enough to take over a passkey-less
      # account; the invite code (or a signed device link) is the proof.
      create(:user, email: "noenroll@example.com")
      post "/api/v1/auth/passkey/register/begin", params: { email: "noenroll@example.com" }
      expect(response).to have_http_status(:forbidden)
    end

    it "lets an existing user without a passkey enroll their first one with an invite" do
      create(:user, email: "noenroll@example.com")
      invite = create(:invite_code)
      post "/api/v1/auth/passkey/register/begin",
           params: { email: "noenroll@example.com", invite_code: invite.code }
      expect(response).to have_http_status(:ok)
    end

    it "rejects a passkey-enrolled user (must sign in instead)" do
      user = create(:user, email: "enrolled@example.com")
      create_webauthn_credential_for(user)

      post "/api/v1/auth/passkey/register/begin", params: { email: "enrolled@example.com" }
      expect(response).to have_http_status(:conflict)
    end

    it "rejects open registration when disabled and no invite given" do
      original = ENV["FIN_OPEN_REGISTRATION"]
      ENV["FIN_OPEN_REGISTRATION"] = "false"
      post "/api/v1/auth/passkey/register/begin", params: { email: "stranger@example.com" }
      expect(response).to have_http_status(:forbidden)
    ensure
      ENV["FIN_OPEN_REGISTRATION"] = original
    end

    it "rejects a used invite code" do
      invite = create(:invite_code, used_at: 1.minute.ago, used_by: create(:user))
      post "/api/v1/auth/passkey/register/begin", params: { email: "n@example.com", invite_code: invite.code }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "register/finish + login/finish round-trip" do
    it "creates the user + credential + token, then can sign in" do
      # ---- register ----
      post "/api/v1/auth/passkey/register/begin", params: { email: "roundtrip@example.com", name: "Round" }
      expect(response).to have_http_status(:ok)
      begin_body = response.parsed_body

      attestation = fake_client.create(challenge: begin_body.dig("options", "challenge"))
      post "/api/v1/auth/passkey/register/finish", params: {
        credential:      attestation,
        challenge_token: begin_body["challenge_token"]
      }
      expect(response).to have_http_status(:created)
      session = response.parsed_body
      expect(session["token"]).to be_present
      expect(session.dig("user", "email")).to eq("roundtrip@example.com")
      expect(session.dig("household", "name")).to eq("Round's Household")

      user = User.find_by(email: "roundtrip@example.com")
      expect(user.webauthn_credentials.count).to eq(1)

      # ---- log in ----
      post "/api/v1/auth/passkey/login/begin", params: { email: "roundtrip@example.com" }
      expect(response).to have_http_status(:ok)
      login_begin = response.parsed_body

      assertion = fake_client.get(challenge: login_begin.dig("options", "challenge"))
      post "/api/v1/auth/passkey/login/finish", params: {
        credential:      assertion,
        challenge_token: login_begin["challenge_token"]
      }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["token"]).to be_present
    end
  end

  describe "invite-based registration" do
    it "attaches the new user to the invite's household and consumes the invite" do
      target_household = create(:household, name: "Invitees")
      invite = create(:invite_code, household: target_household, role: "admin")

      post "/api/v1/auth/passkey/register/begin", params: {
        email: "invited@example.com", invite_code: invite.code
      }
      expect(response).to have_http_status(:ok)
      begin_body = response.parsed_body

      attestation = fake_client.create(challenge: begin_body.dig("options", "challenge"))
      post "/api/v1/auth/passkey/register/finish", params: {
        credential: attestation, challenge_token: begin_body["challenge_token"]
      }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("household", "name")).to eq("Invitees")
      expect(invite.reload).to be_used
      user = User.find_by(email: "invited@example.com")
      expect(user.household_memberships.find_by(household: target_household).role).to eq(Role::Admin)
    end
  end

  describe "challenge token integrity" do
    it "rejects a tampered challenge token" do
      post "/api/v1/auth/passkey/register/finish", params: {
        credential: { id: "x", type: "public-key", rawId: "", response: {} },
        challenge_token: "obviously-not-signed"
      }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # The relying party is assembled per request, and a misconfigured override
  # used to be able to make it unusable: FIN_WEBAUTHN_ORIGINS won outright,
  # so a deploy that templated an empty hostname into "https://" rejected
  # every ceremony with OriginVerificationError and nothing said why.
  describe "allowed origin resolution" do
    it "still verifies when the configured origins are degenerate" do
      with_env("FIN_WEBAUTHN_ORIGINS" => "https://") do
        expect(register_ceremony(fake_client)).to have_http_status(:created)
      end
    end

    it "still verifies when the configured origins point at another host" do
      with_env("FIN_WEBAUTHN_ORIGINS" => "https://elsewhere.example.org") do
        expect(register_ceremony(fake_client)).to have_http_status(:created)
      end
    end

    it "accepts a configured origin written with a trailing slash" do
      # Only the configured entry can match here — the client's origin is not
      # the request's own host — so this fails unless it is normalized.
      client = WebAuthn::FakeClient.new("https://other.example.com")
      with_env("FIN_WEBAUTHN_ORIGINS" => "https://other.example.com/") do
        expect(register_ceremony(client, rp_id: "www.example.com")).to have_http_status(:created)
      end
    end

    it "accepts a configured origin written with the scheme's default port" do
      client = WebAuthn::FakeClient.new("https://other.example.com")
      with_env("FIN_WEBAUTHN_ORIGINS" => "https://other.example.com:443") do
        expect(register_ceremony(client, rp_id: "www.example.com")).to have_http_status(:created)
      end
    end

    it "drops a configured entry that is not an origin, and says so" do
      expect(Rails.logger).to receive(:warn).with(/ignoring unusable FIN_WEBAUTHN_ORIGINS/).at_least(:once)
      with_env("FIN_WEBAUTHN_ORIGINS" => "www.example.com,https://ok.example.com/path") do
        expect(register_ceremony(fake_client)).to have_http_status(:created)
      end
    end

    it "admits an Origin header on a subdomain of the RP ID" do
      # The browser permits an rp_id that is a registrable suffix of the page
      # origin, so the server has to accept the same relation.
      client = WebAuthn::FakeClient.new("http://app.www.example.com")
      response = register_ceremony(client, rp_id: "www.example.com",
                                   headers: { "Origin" => "http://app.www.example.com" })
      expect(response).to have_http_status(:created)
    end

    it "refuses an Origin header from an unrelated host" do
      client = WebAuthn::FakeClient.new("https://evil.example.com")
      response = register_ceremony(client, rp_id: "www.example.com",
                                   headers: { "Origin" => "https://evil.example.com" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/OriginVerificationError/)
    end

    it "warns when the request's own Origin cannot match" do
      expect(Rails.logger).to receive(:warn).with(/will fail OriginVerificationError/).at_least(:once)
      client = WebAuthn::FakeClient.new("https://evil.example.com")
      register_ceremony(client, rp_id: "www.example.com",
                        headers: { "Origin" => "https://evil.example.com" })
    end
  end

  private

  # Helpers --------------------------------------------------------------------

  # Creates a real, verifiable credential for the user using the fake WebAuthn
  # client. The credential bytes match what the fake client would produce on
  # a subsequent sign-in, so login specs can complete the assertion ceremony.
  # Sign-in links for an instance move (Auth::DeviceInvite): long-lived, so
  # narrowed to one host and one use.
  describe "device invite links bound to an address" do
    let(:user) do
      create(:user, email: "mover@example.com").tap { |u| create(:household_membership, user: u) }
    end

    def link_for(host)
      Auth::DeviceInvite.issue(user: user, host: host).token
    end

    def redeem(invite_token)
      post "/api/v1/auth/passkey/device_invite/begin", params: { invite_token: invite_token }
      return response unless response.successful?

      started = response.parsed_body
      post "/api/v1/auth/passkey/device_invite/finish", params: {
        credential: fake_client.create(challenge: started.dig("options", "challenge")),
        challenge_token: started["challenge_token"], nickname: "New home"
      }, as: :json
      response
    end

    it "enrolls a passkey and signs in at the address it was issued for" do
      # The account's old passkeys came along in the restore; they don't
      # stand in the way of the link.
      travel_to(1.day.ago) { create_webauthn_credential_for(user) }

      expect(redeem(link_for("www.example.com"))).to have_http_status(:created)
      expect(response.parsed_body["token"]).to be_present
      expect(user.webauthn_credentials.count).to eq(2)
    end

    it "is refused anywhere else, saying where it belongs" do
      expect(redeem(link_for("fin.newhome.example"))).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("fin.newhome.example")
      expect(user.webauthn_credentials).to be_empty
    end

    it "works once" do
      token = link_for("www.example.com")
      expect(redeem(token)).to have_http_status(:created)

      expect(redeem(token)).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("already been used")
      expect(user.webauthn_credentials.count).to eq(1)
    end

    it "outlives the fifteen minutes of a plain invite, but not its week" do
      token = link_for("www.example.com")

      travel_to(6.days.from_now) do
        post "/api/v1/auth/passkey/device_invite/begin", params: { invite_token: token }
        expect(response).to have_http_status(:ok)
      end
      travel_to(8.days.from_now) do
        post "/api/v1/auth/passkey/device_invite/begin", params: { invite_token: token }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "still honors a plain invite at any address, any number of devices" do
      token = Auth::DeviceInvite.issue(user: user).token

      expect(redeem(token)).to have_http_status(:created)
    end
  end

  def create_webauthn_credential_for(user)
    fake = WebAuthn::FakeClient.new(origin)
    relying_party = WebAuthn::RelyingParty.new(
      id: URI(origin).host, name: "Fin", allowed_origins: [ origin ]
    )
    options = WebAuthn::Credential.options_for_create(
      user: { id: SecureRandom.uuid, name: user.email, display_name: user.email },
      relying_party: relying_party
    )
    attestation = fake.create(challenge: options.challenge)
    credential = WebAuthn::Credential.from_create(attestation, relying_party: relying_party)
    user.webauthn_credentials.create!(
      external_id: credential.id, public_key: credential.public_key, sign_count: credential.sign_count
    )
  end
  # Runs a full registration ceremony for a fresh email and returns the
  # /finish response, so origin-resolution specs assert on one line.
  def register_ceremony(client, rp_id: nil, headers: {})
    email = "ceremony-#{SecureRandom.hex(4)}@example.com"
    post "/api/v1/auth/passkey/register/begin",
         params: { email: email, name: "Ceremony" }, headers: headers
    expect(response).to have_http_status(:ok)
    begin_body = response.parsed_body

    attestation = client.create(
      challenge: begin_body.dig("options", "challenge"),
      rp_id:     rp_id || begin_body.dig("options", "rp", "id")
    )
    post "/api/v1/auth/passkey/register/finish",
         params: { credential: attestation, challenge_token: begin_body["challenge_token"] },
         headers: headers
    response
  end

  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
