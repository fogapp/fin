require "rails_helper"

RSpec.describe "Api::V1::Preferences", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/preferences" do
    it "returns 401 without authentication" do
      get "/api/v1/preferences"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns an empty preferences hash for a new user" do
      get "/api/v1/preferences", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("data" => {})
    end

    it "returns the user's stored preference data" do
      Current.user.create_preference!(data: { "theme" => "dark" })
      get "/api/v1/preferences", headers: auth_headers
      expect(response.parsed_body["data"]).to eq("theme" => "dark")
    end
  end

  describe "PATCH /api/v1/preferences" do
    it "creates the preference if missing and merges the supplied keys" do
      expect {
        patch "/api/v1/preferences",
              params: { data: { theme: "dark" } },
              headers: auth_headers, as: :json
      }.to change { Current.user.reload.preference }.from(nil)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("theme" => "dark")
    end

    it "deep-merges new keys into existing preferences" do
      Current.user.create_preference!(data: { "theme" => "dark", "nested" => { "a" => 1 } })

      patch "/api/v1/preferences",
            params: { data: { nested: { b: 2 } } },
            headers: auth_headers, as: :json

      expect(response.parsed_body["data"]).to eq(
        "theme" => "dark",
        "nested" => { "a" => 1, "b" => 2 }
      )
    end
  end

  describe "appearance scoped to the household" do
    let(:other_household) { create(:household) }
    let(:other_headers) do
      other = create(:api_token, user: token.user, household: other_household)
      { "Authorization" => "Bearer #{other.raw_token}" }
    end

    it "keeps each household's theme, font and size separate for the same user" do
      patch "/api/v1/preferences",
            params: { data: { theme: "dark", font: "inter", font_size: "lg" } },
            headers: auth_headers, as: :json
      patch "/api/v1/preferences",
            params: { data: { theme: "sand" } },
            headers: other_headers, as: :json

      get "/api/v1/preferences", headers: auth_headers
      expect(response.parsed_body["data"]).to include("theme" => "dark", "font" => "inter", "font_size" => "lg")

      get "/api/v1/preferences", headers: other_headers
      expect(response.parsed_body["data"]).to include("theme" => "sand")
      expect(response.parsed_body["data"]).not_to include("font", "font_size")
    end

    it "falls back to the user-wide appearance for a household without its own" do
      token.user.create_preference!(data: { "theme" => "midnight" })

      patch "/api/v1/preferences",
            params: { data: { theme: "rose" } },
            headers: auth_headers, as: :json

      get "/api/v1/preferences", headers: other_headers
      expect(response.parsed_body["data"]).to eq("theme" => "midnight")
    end

    it "shares non-appearance preferences across households" do
      patch "/api/v1/preferences",
            params: { data: { transactions: { page_size: 100 } } },
            headers: auth_headers, as: :json

      get "/api/v1/preferences", headers: other_headers
      expect(response.parsed_body["data"]).to eq("transactions" => { "page_size" => 100 })
    end

    it "never exposes the per-household store" do
      patch "/api/v1/preferences",
            params: { data: { theme: "dark", households: { "x" => { "theme" => "rose" } } } },
            headers: auth_headers, as: :json

      expect(response.parsed_body["data"]).to eq("theme" => "dark")
      expect(token.user.reload.preference.data["households"].keys).to eq([ token.household_id ])
    end
  end
end
