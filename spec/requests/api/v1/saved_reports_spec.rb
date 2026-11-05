require "rails_helper"

RSpec.describe "Api::V1::SavedReports", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  it "returns 401 without authentication" do
    get "/api/v1/saved_reports"
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates, lists, and destroys a report" do
    post "/api/v1/saved_reports",
         params: {
           name: "Joint card · common",
           config: { section: "flow", hash: "section=flow&mode=common", preset: "3m", account_id: "a1" }
         },
         headers: auth_headers, as: :json

    expect(response).to have_http_status(:created)
    id = response.parsed_body["id"]
    expect(response.parsed_body["config"]).to include("hash" => "section=flow&mode=common", "preset" => "3m")

    get "/api/v1/saved_reports", headers: auth_headers
    expect(response.parsed_body.map { |r| r["name"] }).to eq([ "Joint card · common" ])

    delete "/api/v1/saved_reports/#{id}", headers: auth_headers
    expect(response).to have_http_status(:no_content)
    get "/api/v1/saved_reports", headers: auth_headers
    expect(response.parsed_body).to be_empty
  end

  it "requires a name and a config" do
    post "/api/v1/saved_reports", params: { name: "x" }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "does not list another household's reports" do
    Current.set(household: create(:household)) do
      SavedReport.create!(name: "Theirs", config: { hash: "section=flow" }.to_json)
    end

    get "/api/v1/saved_reports", headers: auth_headers
    expect(response.parsed_body).to be_empty
  end
end
