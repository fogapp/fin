require "rails_helper"

RSpec.describe "Api::V1::Tax::Reports", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/tax/report" do
    it "returns the full year report with kind markers and seeds the checklist first" do
      create(:tax_profile, tax_year: 2026, projected_wages: 300_000)
      broker  = create(:broker, name: "Vanguard")
      account = create(:account, broker: broker)
      create(:investment_transaction, account: account, trade_date: Date.new(2026, 3, 1))

      get "/api/v1/tax/report", params: { year: 2026 }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include(
        "year", "generated_at", "profile", "income", "deductions",
        "liability", "payments", "contributions", "flags", "documents"
      )
      expect(body["year"]).to eq(2026)
      expect(body.dig("income", "kind")).to eq("fact")
      expect(body.dig("payments", "kind")).to eq("record")
      expect(body.dig("liability", "kind")).to eq("estimate")
      expect(body.dig("income", "interest")).to be_a(Float).or be_a(Integer)

      # The GET seeded the checklist (W-2 from the profile, 1099 from the broker).
      kinds = body.dig("documents", "items").map { |i| i["kind"] }
      expect(kinds).to include("w2", "1099_consolidated")
      expect(TaxChecklistItem.where(tax_year: 2026, auto_seeded: true)).to be_present
    end

    it "defaults to the current year" do
      get "/api/v1/tax/report", headers: auth_headers
      expect(response.parsed_body["year"]).to eq(Date.current.year)
    end

    it "seeds only on the first GET — later GETs perform no writes" do
      create(:tax_profile, tax_year: 2026, projected_wages: 300_000)

      get "/api/v1/tax/report", params: { year: 2026 }, headers: auth_headers
      expect(TaxChecklistItem.where(tax_year: 2026)).to be_present

      expect(::Tax::ChecklistSeeder).not_to receive(:ensure!)
      expect {
        get "/api/v1/tax/report", params: { year: 2026 }, headers: auth_headers
      }.not_to change(TaxChecklistItem, :count)
      expect(response).to have_http_status(:ok)
    end

    it "is cached: a matching ETag serves 304 and a tax write rotates it" do
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      create(:tax_profile, tax_year: 2026, projected_wages: 300_000)

      # First GET seeds the checklist (a write); the ETag captured afterwards
      # reflects the post-seed DataVersion.
      get "/api/v1/tax/report", params: { year: 2026 }, headers: auth_headers
      get "/api/v1/tax/report", params: { year: 2026 }, headers: auth_headers
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/api/v1/tax/report", params: { year: 2026 },
          headers: auth_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:not_modified)

      # Tax-specific models bump the household DataVersion, so a new payment
      # invalidates the cached report.
      create(:estimated_tax_payment, tax_year: 2026, amount: 1_000)
      get "/api/v1/tax/report", params: { year: 2026 },
          headers: auth_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    ensure
      Rails.cache = original
    end

    it "never leaks another household's data" do
      create(:tax_profile, tax_year: 2026, projected_wages: 300_000)
      create(:estimated_tax_payment, tax_year: 2026, amount: 5_000)

      other_household = create(:household)
      other_user      = create(:user, email: "other@example.com")
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)

      get "/api/v1/tax/report", params: { year: 2026 },
          headers: { "Authorization" => "Bearer #{other_token.raw_token}" }

      body = response.parsed_body
      expect(body["profile"]).to be_nil
      expect(body["liability"]).to be_nil
      expect(body.dig("payments", "federal", "estimated")).to be_empty
      expect(body.dig("documents", "items")).to be_empty
    end
  end
end
