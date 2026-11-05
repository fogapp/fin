require "rails_helper"

RSpec.describe "Api::V1::Plaid::LinkTokens", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/plaid/link_token" do
    it "returns a link token on success" do
      client = instance_double(PlaidClient)
      allow(PlaidClient).to receive(:new).and_return(client)
      allow(client).to receive(:create_link_token).and_return(
        double(link_token: "link-sandbox-abc123")
      )

      post "/api/v1/plaid/link_token", headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["link_token"]).to eq("link-sandbox-abc123")
    end

    it "returns 422 with a static message when an unexpected error fires (A3)" do
      client = instance_double(PlaidClient)
      allow(PlaidClient).to receive(:new).and_return(client)
      # NoMethodError or similar internal error must not leak its message
      # to the API client; we should see only the static fallback.
      allow(client).to receive(:create_link_token).and_raise(
        NoMethodError, "undefined method 'foo' for #<Internal::Thing>"
      )

      post "/api/v1/plaid/link_token", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Failed to create Plaid link token")
      expect(response.parsed_body["error"]).not_to include("Internal")
    end

    it "surfaces the Plaid error_message when Plaid::ApiError fires (A3)" do
      client = instance_double(PlaidClient)
      allow(PlaidClient).to receive(:new).and_return(client)
      api_error = ::Plaid::ApiError.new(message: "Bad")
      allow(api_error).to receive(:response_body).and_return(
        { error_message: "INVALID_API_KEYS", error_code: "INVALID_API_KEYS" }.to_json
      )
      allow(client).to receive(:create_link_token).and_raise(api_error)

      post "/api/v1/plaid/link_token", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_API_KEYS")
    end

    it "says Plaid isn't set up when neither the household nor the deployment has credentials" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PLAID_CLIENT_ID").and_return(nil)
      allow(ENV).to receive(:[]).with("PLAID_SECRET").and_return(nil)

      post "/api/v1/plaid/link_token", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("Plaid isn't set up for this household")
    end

    it "requires authentication" do
      post "/api/v1/plaid/link_token"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
