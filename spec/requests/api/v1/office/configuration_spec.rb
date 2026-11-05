require "rails_helper"

RSpec.describe "Api::V1::Office::Configuration", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/office/configuration" do
    it "returns 401 without authentication" do
      get "/api/v1/office/configuration"
      expect(response).to have_http_status(:unauthorized)
    end

    it "reports the unconfigured state and still lists the datasets" do
      get "/api/v1/office/configuration", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("configured" => false, "api_key_set" => false, "source" => nil)
      expect(response.parsed_body["datasets"].map { |d| d["key"] })
        .to contain_exactly("transactions", "holdings", "portfolio")
    end

    it "reports the base URL but never the token" do
      OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "office_secret")

      get "/api/v1/office/configuration", headers: auth_headers

      expect(response.parsed_body).to include(
        "configured" => true, "base_url" => "https://office.test",
        "api_key_set" => true, "source" => "configuration"
      )
      expect(response.body).not_to include("office_secret")
    end

    it "credits the environment when the connection comes from ENV" do
      stub_const("ENV", ENV.to_h.merge("OFFICE_URL" => "https://env.test", "OFFICE_API_TOKEN" => "env_tok"))

      get "/api/v1/office/configuration", headers: auth_headers

      expect(response.parsed_body).to include("configured" => true, "base_url" => "https://env.test", "source" => "environment")
    end
  end

  describe "PATCH /api/v1/office/configuration" do
    it "saves the instance URL and token" do
      patch "/api/v1/office/configuration",
            params: { office_configuration: { base_url: "https://office.test", api_key: "office_tok" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("configured" => true, "base_url" => "https://office.test")
      config = OfficeConfiguration.unscoped.find_by(household: token.household)
      expect(config.api_key).to eq("office_tok")
    end

    it "keeps the saved token when only the URL is sent" do
      OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "keep")

      patch "/api/v1/office/configuration",
            params: { office_configuration: { base_url: "https://office.test/" } },
            headers: auth_headers, as: :json

      expect(OfficeConfiguration.unscoped.find_by(household: token.household).api_key).to eq("keep")
    end

    it "rejects a URL that isn't http(s)" do
      patch "/api/v1/office/configuration",
            params: { office_configuration: { base_url: "office.test" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "drops the sheet links when the instance it points at changes" do
      OfficeConfiguration.create!(household: token.household, base_url: "https://old.test", api_key: "k")
      create(:office_sheet_export, household: token.household)

      patch "/api/v1/office/configuration",
            params: { office_configuration: { base_url: "https://new.test" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(OfficeSheetExport.unscoped.where(household: token.household)).to be_empty
    end

    it "keeps the sheet links when only the token is rotated" do
      OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "old")
      create(:office_sheet_export, household: token.household)

      patch "/api/v1/office/configuration",
            params: { office_configuration: { api_key: "new" } },
            headers: auth_headers, as: :json

      expect(OfficeSheetExport.unscoped.where(household: token.household).count).to eq(1)
    end
  end

  describe "DELETE /api/v1/office/configuration" do
    it "removes the connection and forgets the sheets it made" do
      OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "k")
      create(:office_sheet_export, household: token.household)

      delete "/api/v1/office/configuration", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(OfficeConfiguration.unscoped.where(household: token.household)).to be_empty
      expect(OfficeSheetExport.unscoped.where(household: token.household)).to be_empty
    end
  end

  describe "POST /api/v1/office/configuration/test" do
    before { OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "t") }

    it "reports a healthy instance" do
      stub_request(:post, "https://office.test/mcp").to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1,
                result: { tools: [ { name: "create_sheet_from_csv" }, { name: "write_cells" } ] } }.to_json
      )

      post "/api/v1/office/configuration/test", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
      expect(response.parsed_body["tools"]).to include("write_cells")
    end

    it "relays the client's own message when the connection fails" do
      stub_request(:post, "https://office.test/mcp").to_return(status: 401, body: "{}")

      post "/api/v1/office/configuration/test", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("ok" => false, "error" => "Office rejected the API token")
    end
  end
end
