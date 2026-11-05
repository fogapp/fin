require "rails_helper"

RSpec.describe "Api::V1::Imports", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/imports" do
    it "returns 401 without authentication" do
      post "/api/v1/imports"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 400 when no file is provided" do
      post "/api/v1/imports", headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "creates an import record and runs it" do
      csv = Rack::Test::UploadedFile.new(
        StringIO.new("Date,Description,Amount\n2026-01-01,Test,-10.00"),
        "text/csv",
        original_filename: "test.csv"
      )

      allow_any_instance_of(Importers::Dispatcher).to receive(:call)

      post "/api/v1/imports", params: { file: csv }, headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["source_filename"]).to eq("test.csv")
      expect(CsvImport.count).to eq(1)
    end
  end
end
