require "swagger_helper"

RSpec.describe "Core", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── GET /me ──────────────────────────────────────────────────────────────────

  path "/api/v1/me" do
    get "Current user and household" do
      tags "Core"
      produces "application/json"

      response "200", "current user info" do
        schema "$ref" => "#/components/schemas/Me"
        before do
          HouseholdMembership.find_or_create_by!(user: token.user, household: token.household) { |m| m.role = "admin" }
        end
        run_test! do |response|
          expect(response.parsed_body.dig("household", "role")).to eq("admin")
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end
  end

  # ── GET /about ────────────────────────────────────────────────────────────────

  path "/api/v1/about" do
    get "Server build info" do
      tags "Core"
      produces "application/json"

      response "200", "build info returned" do
        schema "$ref" => "#/components/schemas/About"
        run_test!
      end
    end
  end

  # ── Preferences ──────────────────────────────────────────────────────────────

  path "/api/v1/preferences" do
    get "Get user preferences" do
      tags "Preferences"
      produces "application/json"

      response "200", "preferences returned" do
        schema "$ref" => "#/components/schemas/Preferences"
        run_test!
      end
    end

    patch "Update user preferences (deep-merged)" do
      tags "Preferences"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: "Keys to merge into existing preferences" }
        },
        required: %w[data]
      }

      response "200", "preferences updated" do
        schema "$ref" => "#/components/schemas/Preferences"
        let(:body) { { data: { theme: "dark" } } }
        run_test!
      end
    end
  end

  # ── API Tokens ────────────────────────────────────────────────────────────────

  path "/api/v1/api_tokens" do
    get "List API tokens" do
      tags "API Tokens"
      produces "application/json"

      response "200", "tokens listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/ApiToken" }
        before { create(:api_token, user: token.user, household: token.household, name: "CI", expires_at: 30.days.from_now) }
        run_test!
      end
    end

    post "Create an API token" do
      tags "API Tokens"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:       { type: :string, description: "Human-readable label" },
          expires_at: { type: :string, format: "date-time", description: "ISO 8601 expiry; omit for no expiry" }
        }
      }

      response "201", "token created — response includes the raw token value (only shown once)" do
        schema "$ref" => "#/components/schemas/ApiTokenCreated"
        let(:body) { { name: "CI deploy token" } }
        run_test!
      end
    end
  end

  path "/api/v1/api_tokens/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Revoke an API token" do
      tags "API Tokens"

      response "204", "token revoked" do
        let(:id) { create(:api_token, user: token.user, household: token.household).id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  # ── Passkeys (WebAuthn credentials) ─────────────────────────────────────────

  path "/api/v1/webauthn_credentials" do
    get "List the current user's passkeys" do
      tags "Passkeys"
      produces "application/json"

      response "200", "passkeys listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/WebauthnCredential" }
        before do
          token.user.webauthn_credentials.create!(external_id: "cred-1", public_key: "pk", sign_count: 0,
                                                  nickname: "Laptop", last_used_at: 1.day.ago)
        end
        run_test!
      end
    end
  end

  path "/api/v1/webauthn_credentials/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    let(:credential) do
      token.user.webauthn_credentials.create!(external_id: "cred-1", public_key: "pk", sign_count: 0, nickname: "Laptop")
    end

    patch "Rename a passkey" do
      tags "Passkeys"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object, properties: { nickname: { type: :string } }, required: %w[nickname]
      }

      response "200", "passkey renamed" do
        schema "$ref" => "#/components/schemas/WebauthnCredential"
        let(:id)   { credential.id }
        let(:body) { { nickname: "Work laptop" } }
        run_test!
      end

      response "422", "blank nickname" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:id)   { credential.id }
        let(:body) { { nickname: " " } }
        run_test!
      end
    end

    delete "Remove a passkey (not the last one)" do
      tags "Passkeys"

      response "204", "passkey removed" do
        before { token.user.webauthn_credentials.create!(external_id: "cred-2", public_key: "pk", sign_count: 0) }
        let(:id) { credential.id }
        run_test!
      end

      response "422", "only passkey" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { credential.id }
        run_test!
      end
    end
  end

  # ── Device invites ───────────────────────────────────────────────────────────

  path "/api/v1/device_invites" do
    post "Mint a link for adding a passkey on another device, or at another address" do
      tags "Passkeys"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          address: { type: :string, description: "Issue a week-long sign-in link redeemable only at this host or URL (an instance move)" },
          user_id: { type: :string, format: :uuid, description: "Another household member to issue it for (admins, with address)" }
        }
      }
      let(:body) { {} }

      response "201", "device invite created" do
        schema "$ref" => "#/components/schemas/DeviceInvite"
        run_test!
      end

      response "422", "address is not a hostname or URL" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { address: "not a host" } }
        run_test!
      end
    end
  end

  # ── Issues ────────────────────────────────────────────────────────────────────

  path "/api/v1/issues" do
    get "List active issues" do
      tags "Issues"
      produces "application/json"

      response "200", "issues listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Issue" }
        before do
          Issue.raise_once!(key: "reconciliation:a:b", title: "Holdings drifted", body: "Ledger vs broker",
                            severity: Severity::Warning, source: "reconciliation")
        end
        run_test!
      end
    end
  end

  path "/api/v1/issues/dismiss_all" do
    post "Dismiss every active issue, optionally for one source" do
      tags "Issues"
      produces "application/json"
      parameter name: :source, in: :query, type: :string, required: false

      response "200", "issues dismissed" do
        schema "$ref" => "#/components/schemas/IssuesDismissed"
        before { Issue.raise_once!(key: "audit:x", title: "Duplicate holdings", source: "system_audit") }
        run_test! do |response|
          expect(response.parsed_body["dismissed"]).to eq(1)
        end
      end
    end
  end

  path "/api/v1/issues/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Dismiss an issue" do
      tags "Issues"
      produces "application/json"

      response "200", "issue dismissed" do
        schema "$ref" => "#/components/schemas/Issue"
        let(:id) { Issue.create!(title: "Test", severity: "warning", source: "system").id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  # ── First-run setup ──────────────────────────────────────────────────────────

  path "/api/v1/setup" do
    get "Whether this instance still needs its first account" do
      tags "Setup"
      produces "application/json"
      security []

      response "200", "setup status" do
        schema "$ref" => "#/components/schemas/SetupStatus"
        run_test!
      end
    end
  end

  path "/api/v1/setup/restore" do
    post "Restore a fresh instance from a fog backup artifact" do
      tags "Setup"
      consumes "multipart/form-data"
      produces "application/json"
      security []
      parameter name: :artifact, in: :formData, type: :file, required: true, description: "fog-backup artifact"
      parameter name: :confirm_identity, in: :formData, type: :boolean, required: false,
                description: "Accept an artifact produced by a different instance"

      # Only a brand-new instance (no users) may restore through setup.
      before { User.delete_all }

      response "200", "artifact staged; the app restarts to restore it" do
        schema "$ref" => "#/components/schemas/SetupRestoreResult"
        let(:artifact) { Rack::Test::UploadedFile.new(StringIO.new("backup"), "application/gzip", original_filename: "b.tar.gz") }
        before do
          preflight = FogBackup::Preflight::Result.new(errors: [], warnings: [ "Older schema" ], manifest: nil)
          allow(FogBackup::StageRestore).to receive(:call).and_return(preflight)
          allow(FogBackup::Restart).to receive(:schedule!)
        end
        run_test!
      end

      response "422", "artifact failed preflight" do
        schema "$ref" => "#/components/schemas/SetupRestoreResult"
        let(:artifact) { Rack::Test::UploadedFile.new(StringIO.new("not a tarball"), "application/gzip", original_filename: "b.tar.gz") }
        run_test! do |response|
          expect(response.parsed_body.dig("preflight", "ok")).to be(false)
        end
      end

      response "400", "no artifact uploaded" do
        schema "$ref" => "#/components/schemas/SetupRestoreResult"
        let(:artifact) { nil }
        run_test!
      end
    end
  end
end
