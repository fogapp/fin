# frozen_string_literal: true

require "rails_helper"
require "rake"
require "webauthn"
require "webauthn/fake_client"

# Sign in with fog (fog:docs/signin-proposal.md §15). The protocol is the
# vendored fog-client's, tested there against tokens fog signed; these specs
# hold Fin's half: what a verified identity does to Fin's users,
# households and session tokens, how an existing account is proven with its
# passkey, and when Fin stops offering its own sign-in.
RSpec.describe "Sign in with fog", type: :request do
  let(:issuer) { "https://fog.home.test" }
  let(:oidc_env) { { "OIDC_ISSUER" => issuer, "OIDC_CLIENT_ID" => "fin", "OIDC_CLIENT_SECRET" => "s3cret" } }
  let(:fog_env) { { "FOG_API_URL" => "http://fog.test", "FOG_API_TOKEN" => "apptok" } }
  let(:off_fog) { { "FOG_API_URL" => nil, "FOG_API_TOKEN" => nil } }
  let(:fake_client) { WebAuthn::FakeClient.new("http://www.example.com") }

  around { |example| with_env(oidc_env.merge(off_fog)) { example.run } }

  def identity(subject: "person:H/KIM", role: "member", handle: "kim", sid: "sid-1", acr: FogSignin::ACR_PASSKEY)
    FogClient::Signin::Identity.new(issuer: issuer, subject: subject, handle: handle, name: handle.capitalize,
                                    roles: [ role ], sid: sid, acr: acr, amr: [ "hwk", "user" ])
  end

  # The provider answers through the shared flow; stand it in.
  def returns(id, return_to: "/cashflow")
    allow_any_instance_of(FogClient::Signin::Flow).to receive(:finish).and_return([ id, return_to ])
  end

  def fragment(location)
    URI.decode_www_form(URI(location).fragment.to_s).to_h
  end

  # The browser keeps what the callback sets. A pending link is bound to it
  # by __Host-fog_link, which is Secure, and rack-test keeps Secure cookies
  # off plain http, so carry it the way the browser would.
  def callback!
    cookies[FogClient::Signin::Rails::COOKIE] = "browser-binding"
    get "/auth/oidc/callback", params: { code: "c", state: "s" }
    link = Array(response.headers["Set-Cookie"]).join("\n")[/#{FogClient::Signin::Rails::LINK_COOKIE}=([^;\s]+)/, 1]
    cookies[FogClient::Signin::Rails::LINK_COOKIE] = link if link
  end

  def handoff!(code)
    post "/api/v1/handoff", params: { handoff: code }
  end

  def json = response.parsed_body

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  def session_for(raw) = ApiToken.unscoped.find_by!(token_digest: Digest::SHA256.hexdigest(raw))

  # A Fin account the way people have them: registered with a passkey.
  def register_with_passkey(email)
    post "/api/v1/auth/passkey/register/begin", params: { email: email, name: email.split("@").first }
    started = json
    post "/api/v1/auth/passkey/register/finish", params: {
      credential: fake_client.create(challenge: started.dig("options", "challenge")),
      challenge_token: started["challenge_token"]
    }
    expect(response).to have_http_status(:created)
    User.find(json.dig("user", "id"))
  end

  # The link page's passkey ceremony: a proof bound to one pending sign-in.
  def prove_with_passkey(pending)
    post "/api/v1/auth/passkey/link/begin", params: { pending: pending }, as: :json
    expect(response).to have_http_status(:ok)
    begun = json
    post "/api/v1/auth/passkey/link/finish", params: {
      credential: fake_client.get(challenge: begun.dig("options", "challenge")),
      challenge_token: begun["challenge_token"], pending: pending
    }, as: :json
    expect(response).to have_http_status(:ok)
    json["link_token"]
  end

  def empty_fin!
    HouseholdMembership.delete_all
    User.delete_all
    Household.delete_all
  end

  it "is not there off any provider" do
    with_env("OIDC_ISSUER" => nil) { get "/auth/oidc/start" }
    expect(response).to have_http_status(:not_found)
  end

  it "says how to sign in" do
    get "/api/v1/setup"
    expect(json["signin"]).to eq("enabled" => true, "fog_only" => false)
    with_env("OIDC_ISSUER" => nil) { get "/api/v1/setup" }
    expect(json["signin"]).to eq("enabled" => false, "fog_only" => false)
  end

  it "starts by sending the browser to the provider, bound to it by a cookie" do
    start = FogClient::Signin::Flow::Start.new(url: "#{issuer}/oauth2/authorize?client_id=fin&request_uri=x", binding: "b")
    allow_any_instance_of(FogClient::Signin::Flow).to receive(:start) do |_, **kw|
      expect(kw[:return_to]).to eq("/")
      start
    end
    get "/auth/oidc/start", params: { return_to: "//evil.example/" }
    expect(response).to redirect_to(start.url)
    expect(response.headers["Set-Cookie"]).to include("__Host-fog_signin=b").and include("secure").and include("httponly")
  end

  it "makes the first person on a fresh Fin the admin of a new household, as registration would" do
    empty_fin!
    returns(identity(role: "admin", handle: "alex", subject: "person:H/ALEX"))
    callback!
    expect(response).to have_http_status(:found)
    expect(response.location).to start_with("http://www.example.com/auth/complete#")
    expect(fragment(response.location)["return_to"]).to eq("/cashflow")

    handoff!(fragment(response.location)["handoff"])
    expect(response).to have_http_status(:created)
    user = User.find(json.dig("user", "id"))
    expect(user.identities.pluck(:issuer, :subject)).to eq([ [ issuer, "person:H/ALEX" ] ])
    expect(user.email).to end_with("@fog.invalid")
    expect(json.dig("household", "role")).to eq("admin")
    household = Household.sole
    expect(household.name).to eq("Alex's Household")
    expect(Workflow.unscoped.where(household_id: household.id)).to exist # the defaults registration seeds

    get "/api/v1/me", headers: bearer(json["token"])
    expect(response).to have_http_status(:ok)
    expect(json.dig("user", "id")).to eq(user.id)
  end

  context "with accounts already in Fin" do
    let!(:kim) { register_with_passkey("kim@example.com") }

    it "never links by email: an unlinked identity is asked to prove an account is theirs" do
      returns(identity.tap { |i| i.email = "kim@example.com" })
      callback!
      expect(response.location).to start_with("http://www.example.com/auth/link#")
      expect(Identity.count).to eq(0)
      expect(ApiToken.where(oidc_sid: "sid-1")).to be_empty
    end

    it "links an account once its owner signs in to it with its passkey, then signs in by identity" do
      returns(identity)
      callback!
      pending = fragment(response.location)["pending"]

      post "/auth/oidc/link", params: { pending: pending }, headers: bearer("not-a-proof"), as: :json
      expect(response).not_to be_successful
      expect(Identity.count).to eq(0)

      proof = prove_with_passkey(pending)
      post "/auth/oidc/link", params: { pending: pending }, headers: bearer(proof), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["return_to"]).to eq("/cashflow")
      handoff!(json["handoff"])
      expect(json.dig("user", "id")).to eq(kim.id)
      expect(kim.identities.pluck(:subject)).to eq([ "person:H/KIM" ])

      callback!
      expect(response.location).to start_with("http://www.example.com/auth/complete#")
    end

    it "takes a passkey proof only for the pending sign-in it was made for" do
      returns(identity)
      callback!
      proof = prove_with_passkey(fragment(response.location)["pending"])

      returns(identity(subject: "person:H/SOMEONE", handle: "someone"))
      callback!
      other = fragment(response.location)["pending"]
      post "/auth/oidc/link", params: { pending: other }, headers: bearer(proof), as: :json
      expect(response).not_to be_successful
      expect(Identity.count).to eq(0)
    end

    it "offers no account that is already connected to someone at this provider" do
      Identity.create!(user: kim, issuer: issuer, subject: "person:H/KIM")
      returns(identity(subject: "person:H/SOMEONE", handle: "someone"))
      callback!
      pending = fragment(response.location)["pending"]
      post "/auth/oidc/link", params: { pending: pending }, headers: bearer(prove_with_passkey(pending)), as: :json
      expect(response).not_to be_successful
      expect(kim.identities.count).to eq(1)
    end

    it "does not hand out a session for the passkey proof" do
      returns(identity)
      callback!
      proof = prove_with_passkey(fragment(response.location)["pending"])
      get "/api/v1/me", headers: bearer(proof)
      expect(response).to have_http_status(:unauthorized)
    end

    it "starts a fresh account in the family's household when the person asks" do
      returns(identity)
      callback!
      post "/auth/oidc/link", params: { pending: fragment(response.location)["pending"], fresh: "true" }, as: :json
      handoff!(json["handoff"])
      fresh = User.find(json.dig("user", "id"))
      expect(fresh).not_to eq(kim)
      family = Household.order(:created_at).first
      expect(fresh.household_memberships.pluck(:household_id, :role)).to eq([ [ family.id, Role::Member ] ])
    end

    it "links nothing from a browser other than the one fog sent back" do
      users = User.count
      returns(identity)
      callback!
      pending = fragment(response.location)["pending"]
      expect(response.headers["Set-Cookie"].to_s).to include("__Host-fog_link=").and include("samesite=strict")
      proof = prove_with_passkey(pending)

      cookies.delete(FogClient::Signin::Rails::LINK_COOKIE)
      post "/auth/oidc/link", params: { pending: pending }, headers: bearer(proof), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      cookies[FogClient::Signin::Rails::LINK_COOKIE] = "another-browser"
      post "/auth/oidc/link", params: { pending: pending, fresh: "true" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(Identity.count).to eq(0)
      expect(User.count).to eq(users)
    end

    it "refuses a visitor from a paired household: Fin hosts none" do
      users = User.count
      returns(identity(subject: "person:OTHER/DAVE", handle: "dave").tap { |i| i.visitor = true; i.home = "OTHER" })
      callback!
      expect(fragment(response.location)).to eq("signin_error" => "visitors_not_hosted")
      expect(Identity.count).to eq(0)
      expect(User.count).to eq(users)
    end

    it "refuses a pending link that was tampered with" do
      post "/auth/oidc/link", params: { pending: "not-sealed", fresh: "true" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/v1/auth/passkey/link/begin", params: { pending: "not-sealed" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "roles" do
    let(:family) { Household.order(:created_at).first }
    let(:kim) { create(:user) }

    before do
      create(:household_membership, user: kim, household: family, role: "member")
      Identity.create!(user: kim, issuer: issuer, subject: "person:H/KIM")
    end

    def kims_role = kim.household_memberships.find_by!(household: family).role

    it "takes the role fog decided, in the family's household, every sign-in" do
      returns(identity(role: "admin"))
      callback!
      expect(kims_role).to eq(Role::Admin)
      returns(identity(role: "member"))
      callback!
      expect(kims_role).to eq(Role::Member)
    end

    it "never demotes the household's last admin, and ignores a role it does not know" do
      family.household_memberships.where.not(user: kim).delete_all
      family.household_memberships.find_by!(user: kim).update!(role: Role::Admin)
      returns(identity(role: "member"))
      callback!
      expect(kims_role).to eq(Role::Admin)
      returns(identity(role: "viewer"))
      callback!
      expect(kims_role).to eq(Role::Admin)
    end

    it "lands the session in the household the person joined first" do
      cabin = create(:household, name: "Cabin")
      kim.household_memberships.update_all(created_at: 1.day.ago)
      create(:household_membership, user: kim, household: cabin, role: "admin")
      returns(identity)
      callback!
      handoff!(fragment(response.location)["handoff"])
      expect(json.dig("household", "id")).to eq(family.id)
    end

    it "sends someone with no household back to sign-in, saying why" do
      kim.household_memberships.delete_all
      returns(identity)
      callback!
      expect(response.location).to eq("http://www.example.com/login#signin_error=no_household")
    end
  end

  describe "handoff" do
    before { Identity.create!(user: Current.user, issuer: issuer, subject: "person:H/KIM") }

    it "is good once" do
      returns(identity)
      callback!
      code = fragment(response.location)["handoff"]
      handoff!(code)
      expect(response).to have_http_status(:created)
      handoff!(code)
      expect(response).to have_http_status(:unauthorized)
    end

    it "is good for a minute" do
      returns(identity)
      callback!
      code = fragment(response.location)["handoff"]
      travel 2.minutes do
        handoff!(code)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "carries the provider's session and a lifetime" do
      returns(identity(sid: "sid-9"))
      callback!
      handoff!(fragment(response.location)["handoff"])
      session = session_for(json["token"])
      expect(session).to have_attributes(session: true, oidc_sid: "sid-9", name: "fog session")
      expect(session.expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  describe "back-channel logout" do
    let(:kim) { Current.user }
    let(:household) { Current.household }

    def logout!(sid: nil, subject: nil)
      allow_any_instance_of(FogClient::Signin::Backchannel).to receive(:verify)
        .and_return(FogClient::Signin::Backchannel::Logout.new(subject: subject, sid: sid, jti: SecureRandom.hex(4)))
      post "/auth/oidc/backchannel", params: { logout_token: "t" }
    end

    it "ends exactly the sessions the provider names" do
      fog = Auth::SessionToken.mint!(user: kim, household: household, oidc_sid: "sid-1")
      other = Auth::SessionToken.mint!(user: kim, household: household, oidc_sid: "sid-2")
      logout!(sid: "sid-1")
      expect(response).to have_http_status(:ok)
      expect(ApiToken.exists?(fog.id)).to be(false)
      expect(ApiToken.exists?(other.id)).to be(true)
    end

    it "follows a session into another household" do
      fog = Auth::SessionToken.mint!(user: kim, household: household, oidc_sid: "sid-1", expires_at: 2.days.from_now)
      cabin = create(:household, name: "Cabin")
      create(:household_membership, user: kim, household: cabin, role: "member")
      post "/api/v1/auth/switch_household", params: { household_id: cabin.id }, headers: bearer(fog.raw_token)
      switched = session_for(json["token"])
      expect(switched).to have_attributes(oidc_sid: "sid-1", household_id: cabin.id)
      expect(switched.expires_at).to be_within(1.second).of(fog.expires_at)

      logout!(sid: "sid-1")
      expect(ApiToken.exists?(switched.id)).to be(false)
    end

    it "ends a person's sessions by subject, but not their API tokens" do
      Identity.create!(user: kim, issuer: issuer, subject: "person:H/KIM")
      session = Auth::SessionToken.mint!(user: kim, household: household)
      pat = ApiToken.create!(user: kim, household: household, name: "script")
      bystander = Auth::SessionToken.mint!(user: create(:user), household: household)
      logout!(subject: "person:H/KIM")
      expect(ApiToken.exists?(session.id)).to be(false)
      expect(ApiToken.exists?(pat.id)).to be(true)
      expect(ApiToken.exists?(bystander.id)).to be(true)
    end

    it "refuses a token that does not verify" do
      allow_any_instance_of(FogClient::Signin::Backchannel).to receive(:verify).and_raise(FogClient::Signin::Invalid, "bad")
      post "/auth/oidc/backchannel", params: { logout_token: "t" }
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "lets an expired session go" do
    session = Auth::SessionToken.mint!(user: Current.user, household: Current.household, oidc_sid: "s",
      expires_at: 1.minute.from_now)
    travel 2.minutes do
      get "/api/v1/me", headers: bearer(session.raw_token)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "fog only" do
    let!(:kim) { register_with_passkey("kim@example.com") }

    def passkey_login
      post "/api/v1/auth/passkey/login/begin", params: {}, as: :json
    end

    it "turns Fin's own sign-in off once Fin has proven it runs on fog" do
      with_env(fog_env) do
        allow(FogClient::Signin::Proof).to receive(:check).and_return(false)
        get "/api/v1/setup"
        expect(json["signin"]).to eq("enabled" => true, "fog_only" => false)
        passkey_login
        expect(response).to have_http_status(:ok)

        allow(FogClient::Signin::Proof).to receive(:check).and_return(true)
        get "/api/v1/setup"
        expect(json["signin"]).to eq("enabled" => true, "fog_only" => true)
        expect(json["setup_required"]).to be(false)
        passkey_login
        expect(response).to have_http_status(:forbidden)
        post "/api/v1/auth/passkey/device_invite/begin", params: { invite_token: "x" }, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "closes registration whatever FIN_OPEN_REGISTRATION says" do
      InstanceSetting.current.update!(fog_attested_at: 1.minute.ago)
      with_env(fog_env.merge("FIN_OPEN_REGISTRATION" => "true")) do
        post "/api/v1/auth/passkey/register/begin", params: { email: "new@example.com" }, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(json["error"]).to eq("Fin signs people in with fog.")
      end
    end

    it "still lets a person prove their account with its passkey to connect it" do
      InstanceSetting.current.update!(fog_attested_at: 1.minute.ago)
      with_env(fog_env) do
        returns(identity)
        callback!
        pending = fragment(response.location)["pending"]
        post "/auth/oidc/link", params: { pending: pending }, headers: bearer(prove_with_passkey(pending)), as: :json
        handoff!(json["handoff"])
        expect(json.dig("user", "id")).to eq(kim.id)
      end
    end

    it "asks fog for a passkey, and refuses a sign-in without one" do
      InstanceSetting.current.update!(fog_attested_at: 1.minute.ago)
      with_env(fog_env) do
        start = FogClient::Signin::Flow::Start.new(url: "#{issuer}/oauth2/authorize?request_uri=x", binding: "b")
        allow_any_instance_of(FogClient::Signin::Flow).to receive(:start) do |_, **kw|
          expect(kw[:acr]).to eq("urn:fog:acr:phr")
          start
        end
        get "/auth/oidc/start"
        expect(response).to redirect_to(start.url)

        returns(identity(acr: "urn:fog:acr:pwd"))
        callback!
        expect(response.location).to eq("http://www.example.com/login#signin_error=passkey_required")
        expect(Identity.count).to eq(0)
      end
    end

    it "stays fog-only when fog cannot be reached, and ends when Fin leaves fog" do
      InstanceSetting.current.update!(fog_attested_at: 1.day.ago)
      with_env(fog_env) do
        allow(FogClient::Signin::Proof).to receive(:check).and_return(false)
        get "/api/v1/setup"
        expect(json.dig("signin", "fog_only")).to be(true)
      end

      get "/api/v1/setup"
      expect(json.dig("signin", "fog_only")).to be(false)
      passkey_login
      expect(response).to have_http_status(:ok)
    end
  end

  it "mints a recovery link from the console that signs the first admin in once" do
    admin = Current.user
    Rails.application.load_tasks unless Rake::Task.task_defined?("fin:recovery_link")
    task = Rake::Task["fin:recovery_link"]
    task.reenable
    out = capture_stdout { task.invoke("fin.example.com") }
    link = out.lines.first.strip
    expect(link).to start_with("https://fin.example.com/auth/complete#")
    code = fragment(link)["handoff"]
    handoff!(code)
    expect(json.dig("user", "id")).to eq(admin.id)
    handoff!(code)
    expect(response).to have_http_status(:unauthorized)
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
