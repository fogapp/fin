require "rails_helper"

RSpec.describe "Api::V1::Plaid::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/plaid/configuration" do
    it "returns the environment default and unconfigured state when no record exists" do
      # The controller treats ENV-supplied Plaid creds as "configured via
      # environment" — clear them for this test so the unconfigured branch
      # is exercised.
      original = ENV.delete("PLAID_CLIENT_ID")
      original_secret = ENV.delete("PLAID_SECRET")
      begin
        get "/api/v1/plaid/configuration", headers: auth_headers
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["client_id_set"]).to be false
        expect(body["secret_set"]).to    be false
        expect(body["configured"]).to    be false
        expect(body["source"]).to        eq("environment")
      ensure
        ENV["PLAID_CLIENT_ID"] = original if original
        ENV["PLAID_SECRET"]    = original_secret if original_secret
      end
    end

    it "reports source=database when a household record is configured" do
      Current.household.plaid_configurations.create!(
        client_id: "c", secret: "s", environment: "sandbox"
      )

      get "/api/v1/plaid/configuration", headers: auth_headers
      body = response.parsed_body
      expect(body["client_id_set"]).to be true
      expect(body["secret_set"]).to    be true
      expect(body["configured"]).to    be true
      expect(body["environment"]).to   eq("sandbox")
      expect(body["source"]).to        eq("database")
    end
  end

  describe "PATCH /api/v1/plaid/configuration" do
    it "creates the configuration on first save" do
      expect {
        patch "/api/v1/plaid/configuration",
              params: { plaid_configuration: { client_id: "c", secret: "s", environment: "sandbox" } },
              headers: auth_headers, as: :json
      }.to change { Current.household.plaid_configurations.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
    end

    it "updates the existing configuration in place" do
      cfg = Current.household.plaid_configurations.create!(
        client_id: "old", secret: "old", environment: "sandbox"
      )

      patch "/api/v1/plaid/configuration",
            params: { plaid_configuration: { client_id: "new" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(cfg.reload.client_id).to eq("new")
    end

    it "returns 422 with the error when the environment is invalid" do
      patch "/api/v1/plaid/configuration",
            params: { plaid_configuration: { client_id: "c", secret: "s", environment: "bogus" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      # A3: the controller's bare `rescue => e` was removed so RecordInvalid
      # now flows through BaseController#render_unprocessable, which uses
      # the standard `errors: [...]` shape.
      expect(response.parsed_body["errors"].join(" ")).to include("Environment")
    end
  end
end
