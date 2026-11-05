require "rails_helper"

RSpec.describe "Api::V1::TaxProfiles", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/tax_profile" do
    it "returns an unpersisted default when the year has no profile" do
      get "/api/v1/tax_profile", params: { year: 2026 }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include(
        "persisted"       => false,
        "tax_year"        => 2026,
        "filing_status"   => "single",
        "state"           => "CA",
        "state_tax_source" => "modeled",
        "projected_state_tax" => nil,
        "projected_wages" => 0.0,
        "complete"        => false
      )
    end

    it "defaults to the current year" do
      get "/api/v1/tax_profile", headers: auth_headers
      expect(response.parsed_body["tax_year"]).to eq(Date.current.year)
    end
  end

  describe "PUT /api/v1/tax_profile" do
    it "upserts by tax_year and roundtrips through GET" do
      put "/api/v1/tax_profile",
          params: { tax_year: 2026, filing_status: "mfj", projected_wages: 332_200,
                    itemizing: true, salt_paid: 40_400, prior_year_total_tax: 50_000,
                    prior_year_agi: 300_000, ytd_withholding_federal: 56_000 },
          headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("persisted" => true, "complete" => true,
                                              "filing_status" => "mfj", "projected_wages" => 332_200.0)

      # Second PUT updates the same row.
      put "/api/v1/tax_profile", params: { tax_year: 2026, projected_wages: 350_000 },
          headers: auth_headers, as: :json
      expect(TaxProfile.count).to eq(1)

      get "/api/v1/tax_profile", params: { year: 2026 }, headers: auth_headers
      body = response.parsed_body
      expect(body).to include("projected_wages" => 350_000.0, "filing_status" => "mfj",
                              "salt_paid" => 40_400.0, "prior_year_total_tax" => 50_000.0,
                              "ytd_withholding_federal" => 56_000.0, "complete" => true)
    end

    it "saves a non-California state with its projected state tax, requiring the amount" do
      put "/api/v1/tax_profile", params: { tax_year: 2026, projected_wages: 200_000, state: "NY" },
          headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("Projected state tax")

      put "/api/v1/tax_profile",
          params: { tax_year: 2026, projected_wages: 200_000, state: "NY", projected_state_tax: 15_000 },
          headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("state" => "NY", "state_name" => "New York",
                                              "projected_state_tax" => 15_000.0, "state_tax_source" => "entered")

      put "/api/v1/tax_profile", params: { tax_year: 2026, state: "TX", projected_state_tax: nil },
          headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("state" => "TX", "projected_state_tax" => nil,
                                              "state_tax_source" => "no_income_tax")
    end

    it "renders 422 on an invalid filing status" do
      put "/api/v1/tax_profile", params: { tax_year: 2026, filing_status: "hoh" },
          headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "household isolation" do
    it "never exposes or overwrites another household's profile" do
      create(:tax_profile, tax_year: 2026, projected_wages: 500_000)

      other_household = create(:household)
      other_user      = create(:user)
      create(:household_membership, user: other_user, household: other_household)
      other_token   = create(:api_token, user: other_user, household: other_household)
      other_headers = { "Authorization" => "Bearer #{other_token.raw_token}" }

      get "/api/v1/tax_profile", params: { year: 2026 }, headers: other_headers
      expect(response.parsed_body).to include("persisted" => false, "projected_wages" => 0.0)

      put "/api/v1/tax_profile", params: { tax_year: 2026, projected_wages: 1 },
          headers: other_headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(TaxProfile.unscoped.count).to eq(2)
      expect(TaxProfile.unscoped.order(:projected_wages).map { |p| p.projected_wages.to_f })
        .to eq([ 1.0, 500_000.0 ])
    end
  end
end
