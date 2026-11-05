require "rails_helper"

RSpec.describe "Api::V1::About", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/about" do
    it "returns 401 without authentication" do
      get "/api/v1/about"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the build and runtime fields the About panel renders" do
      get "/api/v1/about", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include(
        "rails_version", "ruby_version", "rails_env", "git_sha", "git_sha_short", "hostname"
      )
      expect(body["rails_version"]).to eq(Rails::VERSION::STRING)
      expect(body["ruby_version"]).to eq(RUBY_VERSION)
      expect(body["rails_env"]).to eq("test")
    end

    it "exposes the deployed sha and its short form when GIT_SHA is set" do
      sha = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GIT_REV").and_return(nil)
      allow(ENV).to receive(:[]).with("GIT_SHA").and_return(sha)

      get "/api/v1/about", headers: auth_headers

      expect(response.parsed_body).to include("git_sha" => sha, "git_sha_short" => "a1b2c3d")
    end

    it "returns null shas rather than empty strings when no build info is present" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GIT_REV").and_return("")
      allow(ENV).to receive(:[]).with("GIT_SHA").and_return("")

      get "/api/v1/about", headers: auth_headers

      expect(response.parsed_body["git_sha"]).to be_nil
      expect(response.parsed_body["git_sha_short"]).to be_nil
    end
  end
end
