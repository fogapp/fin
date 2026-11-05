require "swagger_helper"
require "webauthn"
require "webauthn/fake_client"

RSpec.describe "Auth", type: :request do
  # The relying party is derived from the request, so the fake client
  # presents the origin Rack::Test requests come from.
  let(:fake_client) { WebAuthn::FakeClient.new("http://www.example.com") }

  # Runs the matching /begin call and returns its body, so a /finish example
  # can answer the challenge it issued.
  def begin_ceremony(path, params)
    post path, params: params
    response.parsed_body
  end

  CEREMONY_BODY = {
    type: :object,
    properties: {
      credential:      { type: :object, additionalProperties: true, description: "The browser's PublicKeyCredential JSON" },
      challenge_token: { type: :string },
      nickname:        { type: :string }
    },
    required: %w[credential challenge_token]
  }.freeze

  path "/api/v1/auth/passkey/register/begin" do
    post "Start passkey registration" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          email:       { type: :string },
          name:        { type: :string },
          invite_code: { type: :string }
        },
        required: %w[email]
      }

      response "200", "creation options issued" do
        schema "$ref" => "#/components/schemas/PasskeyChallenge"
        let(:body) { { email: "new@example.com", name: "New" } }
        run_test!
      end

      response "409", "email already has a passkey" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) do
          user = create(:user, email: "enrolled@example.com")
          user.webauthn_credentials.create!(external_id: "cred", public_key: "pk", sign_count: 0)
          { email: "enrolled@example.com" }
        end
        run_test!
      end
    end
  end

  path "/api/v1/auth/passkey/register/finish" do
    post "Finish passkey registration and start a session" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: CEREMONY_BODY

      response "201", "registered and signed in" do
        schema "$ref" => "#/components/schemas/Session"
        let(:body) do
          started = begin_ceremony("/api/v1/auth/passkey/register/begin", { email: "reg@example.com", name: "Reg" })
          { credential: fake_client.create(challenge: started.dig("options", "challenge")),
            challenge_token: started["challenge_token"], nickname: "Laptop" }
        end
        run_test!
      end
    end
  end

  path "/api/v1/auth/passkey/login/begin" do
    post "Start passkey sign-in" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { email: { type: :string, description: "Omit to let the browser offer any passkey" } }
      }

      response "200", "request options issued" do
        schema "$ref" => "#/components/schemas/PasskeyChallenge"
        let(:body) { {} }
        run_test!
      end
    end
  end

  path "/api/v1/auth/passkey/login/finish" do
    post "Finish passkey sign-in" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: CEREMONY_BODY

      response "200", "signed in" do
        schema "$ref" => "#/components/schemas/Session"
        let(:body) do
          started = begin_ceremony("/api/v1/auth/passkey/register/begin", { email: "login@example.com", name: "Login" })
          post "/api/v1/auth/passkey/register/finish", params: {
            credential: fake_client.create(challenge: started.dig("options", "challenge")),
            challenge_token: started["challenge_token"]
          }
          login = begin_ceremony("/api/v1/auth/passkey/login/begin", { email: "login@example.com" })
          { credential: fake_client.get(challenge: login.dig("options", "challenge")),
            challenge_token: login["challenge_token"] }
        end
        run_test!
      end

      response "401", "bad challenge token" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { credential: {}, challenge_token: "forged" } }
        run_test!
      end
    end
  end

  path "/api/v1/auth/passkey/device_invite/begin" do
    post "Start adding a passkey from a device-invite link" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: {
        type: :object, properties: { invite_token: { type: :string } }, required: %w[invite_token]
      }

      response "200", "creation options issued" do
        schema "$ref" => "#/components/schemas/PasskeyChallenge"
        let(:body) do
          user = create(:user)
          { invite_token: Rails.application.message_verifier(:device_invite).generate(
            { intent: "device_invite", user_id: user.id, email: user.email, name: user.name }, expires_in: 15.minutes
          ) }
        end
        run_test!
      end
    end
  end

  path "/api/v1/auth/passkey/device_invite/finish" do
    post "Finish adding a passkey from a device-invite link" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: CEREMONY_BODY

      response "201", "passkey added and signed in" do
        schema "$ref" => "#/components/schemas/Session"
        let(:body) do
          user = create(:user)
          create(:household_membership, user: user)
          invite_token = Rails.application.message_verifier(:device_invite).generate(
            { intent: "device_invite", user_id: user.id, email: user.email, name: user.name }, expires_in: 15.minutes
          )
          started = begin_ceremony("/api/v1/auth/passkey/device_invite/begin", { invite_token: invite_token })
          { credential: fake_client.create(challenge: started.dig("options", "challenge")),
            challenge_token: started["challenge_token"], nickname: "Phone" }
        end
        run_test!
      end
    end
  end

  # The fog link page (Sign in with fog): prove an existing account with its
  # passkey, for one pending fog sign-in.
  context "with fog sign-in configured" do
    let(:oidc) { { "OIDC_ISSUER" => "https://fog.home.test", "OIDC_CLIENT_ID" => "fin", "OIDC_CLIENT_SECRET" => "s3cret" } }
    let(:pending) do
      FogClient::Signin::State.seal(FogClient::Signin.config(oidc), {
        "identity" => { "issuer" => "https://fog.home.test", "subject" => "person:H/KIM", "roles" => [ "member" ] },
        "return_to" => "/", "e" => 10.minutes.from_now.to_i
      }, purpose: "pending")
    end

    around { |example| with_env(oidc) { example.run } }

    path "/api/v1/auth/passkey/link/begin" do
      post "Start proving an account with its passkey, to connect it to fog" do
        tags "Auth"
        consumes "application/json"
        produces "application/json"
        security []
        parameter name: :body, in: :body, schema: {
          type: :object,
          properties: {
            pending: { type: :string, description: "The sealed fog sign-in the link page was given" },
            email:   { type: :string, description: "Omit to let the browser offer any passkey" }
          },
          required: %w[pending]
        }

        response "200", "request options issued" do
          schema "$ref" => "#/components/schemas/PasskeyChallenge"
          let(:body) { { pending: pending } }
          run_test!
        end

        response "422", "the fog sign-in expired or was tampered with" do
          schema "$ref" => "#/components/schemas/Error"
          let(:body) { { pending: "forged" } }
          run_test!
        end
      end
    end

    path "/api/v1/auth/passkey/link/finish" do
      post "Finish proving an account with its passkey" do
        tags "Auth"
        consumes "application/json"
        produces "application/json"
        security []
        parameter name: :body, in: :body, schema: {
          type: :object,
          properties: CEREMONY_BODY[:properties].merge(pending: { type: :string }),
          required: %w[credential challenge_token pending]
        }

        response "200", "account proven; the link_token is the bearer for POST /auth/oidc/link" do
          schema "$ref" => "#/components/schemas/PasskeyLinkProof"
          let(:body) do
            started = begin_ceremony("/api/v1/auth/passkey/register/begin", { email: "link@example.com", name: "Link" })
            post "/api/v1/auth/passkey/register/finish", params: {
              credential: fake_client.create(challenge: started.dig("options", "challenge")),
              challenge_token: started["challenge_token"]
            }
            link = begin_ceremony("/api/v1/auth/passkey/link/begin", { pending: pending })
            { credential: fake_client.get(challenge: link.dig("options", "challenge")),
              challenge_token: link["challenge_token"], pending: pending }
          end
          run_test!
        end
      end
    end
  end

  path "/api/v1/handoff" do
    post "Trade a sign-in's one-time handoff code for its session" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security []
      parameter name: :body, in: :body, schema: {
        type: :object, properties: { handoff: { type: :string } }, required: %w[handoff]
      }

      response "201", "signed in" do
        schema "$ref" => "#/components/schemas/Session"
        let(:body) do
          session = Auth::SessionToken.mint!(user: Current.user, household: Current.household, label: "fog session")
          { handoff: session.issue_handoff! }
        end
        run_test!
      end

      response "401", "unknown, spent or expired code" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { handoff: "spent" } }
        run_test!
      end
    end
  end

  path "/api/v1/auth/switch_household" do
    post "Mint a session for another of the user's households" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object, properties: { household_id: { type: :string, format: :uuid } }, required: %w[household_id]
      }

      let(:token)         { create(:api_token) }
      let(:Authorization) { "Bearer #{token.raw_token}" }

      response "200", "switched" do
        schema "$ref" => "#/components/schemas/Session"
        let(:body) do
          other = create(:household, name: "Cabin")
          create(:household_membership, user: token.user, household: other, role: "member")
          { household_id: other.id }
        end
        run_test!
      end

      response "403", "not a member" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { household_id: create(:household).id } }
        run_test!
      end
    end
  end
end
