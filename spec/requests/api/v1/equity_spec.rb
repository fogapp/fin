require "rails_helper"

RSpec.describe "Api::V1::Equity", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/equity/summary" do
    it "returns companies with fmv history, grant math, and totals" do
      company = create(:equity_company, name: "Acme", preferred_price: 14.5)
      create(:equity_fmv_entry, equity_company: company, price_per_share: 8,
             effective_date: Date.current - 2.years, source: "409a")
      create(:equity_fmv_entry, equity_company: company, price_per_share: 10,
             effective_date: Date.current - 1.month, source: "round")

      # 100 ISOs at $1: quarterly over the past 7 months → 2 of 4 tranches vested.
      grant = create(:equity_grant, equity_company: company, label: "ISO-1",
                     grant_type: "iso", strike_price: 1, quantity: 100,
                     grant_date: Date.current - 7.months,
                     vesting_interval: "quarterly", vesting_occurrences: 4,
                     cliff_installments: 0)
      create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 20,
             occurred_on: Date.current - 2.days, share_price: 10, method: "cash")

      get "/api/v1/equity/summary", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      c = body["companies"].sole
      expect(c).to include("name" => "Acme", "public_company" => false, "ticker" => nil,
                           "preferred_price" => 14.5, "share_price" => 10.0)
      expect(c["latest_fmv"]).to include("price_per_share" => 10.0, "source" => "round", "stale" => false)
      expect(c["fmv_entries"].map { |e| e["price_per_share"] }).to eq([ 10.0, 8.0 ]) # date desc

      g = c["grants"].sole
      expect(g).to include(
        "label"              => "ISO-1",
        "grant_type"         => "iso",
        "quantity"           => 100.0,
        "strike_price"       => 1.0,
        "vested_quantity"    => 50.0,
        "unvested_quantity"  => 50.0,
        "exercised_quantity" => 20.0,
        "settled_quantity"   => 0.0,
        "sold_quantity"      => 0.0,
        "vested_value"       => 450.0,  # (10 − 1) × 50 intrinsic
        "unvested_value"     => 450.0
      )
      expect(g["next_vest"]).to include("quantity" => 25.0)
      expect(g["tranches"].size).to eq(4)
      expect(g["tranches"].count { |t| t["vested"] }).to eq(2)
      expect(g["events"].sole).to include("kind" => "exercise", "quantity" => 20.0,
                                          "share_price" => 10.0, "method" => "cash")

      totals = body["totals"]
      expect(totals["vested_value"]).to eq(450.0)
      expect(totals["unvested_value"]).to eq(450.0)
      upcoming = totals["upcoming_vests"]
      expect(upcoming.size).to eq(2) # the 2 unvested tranches fall inside 365 days
      expect(upcoming.map { |v| v["date"] }).to eq(upcoming.map { |v| v["date"] }.sort)
      expect(upcoming.first).to include("quantity" => 25.0, "value" => 225.0,
                                        "grant_id" => grant.id, "grant_label" => "ISO-1",
                                        "grant_type" => "iso",
                                        "company_id" => company.id, "company_name" => "Acme")
    end

    it "returns null values when a company has no price" do
      company = create(:equity_company)
      create(:equity_grant, :rsu, :fully_vested, equity_company: company, quantity: 10,
             grant_date: Date.current - 1.year)

      get "/api/v1/equity/summary", headers: auth_headers

      c = response.parsed_body["companies"].sole
      expect(c["share_price"]).to be_nil
      expect(c["latest_fmv"]).to be_nil
      expect(c["grants"].sole["vested_value"]).to be_nil
    end
  end

  describe "companies" do
    it "creates a private company with an initial FMV entry" do
      post "/api/v1/equity/companies",
           params: { name: "Acme", public_company: false, qsbs_candidate: true,
                     initial_fmv: { price_per_share: 4.2, effective_date: "2026-06-01", source: "409a" } },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include("name" => "Acme", "qsbs_candidate" => true, "share_price" => 4.2)
      expect(body["fmv_entries"].sole).to include("price_per_share" => 4.2, "source" => "409a")
    end

    it "links a security for public companies via the resolver" do
      post "/api/v1/equity/companies",
           params: { name: "Apple", public_company: true, ticker: "AAPL" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["ticker"]).to eq("AAPL")
      expect(Security.find(body["security_id"]).ticker).to eq("AAPL")
    end

    it "updates and deletes with cascade" do
      company = create(:equity_company)
      grant = create(:equity_grant, equity_company: company)
      create(:equity_fmv_entry, equity_company: company)
      create(:equity_grant_event, equity_grant: grant, kind: "cancellation", quantity: 1)

      patch "/api/v1/equity/companies/#{company.id}",
            params: { notes: "series B" }, headers: auth_headers, as: :json
      expect(response.parsed_body["notes"]).to eq("series B")

      delete "/api/v1/equity/companies/#{company.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(EquityCompany.count).to eq(0)
      expect(EquityGrant.count).to eq(0)
      expect(EquityFmvEntry.count).to eq(0)
      expect(EquityGrantEvent.count).to eq(0)
    end

    it "renders 422 on validation failure" do
      post "/api/v1/equity/companies", params: { name: "" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "fmv entries" do
    it "creates and deletes entries" do
      company = create(:equity_company)

      post "/api/v1/equity/companies/#{company.id}/fmv_entries",
           params: { price_per_share: 12.5, effective_date: "2026-07-01", source: "tender" },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      entry_id = response.parsed_body["id"]
      expect(response.parsed_body).to include("price_per_share" => 12.5, "source" => "tender")

      post "/api/v1/equity/companies/#{company.id}/fmv_entries",
           params: { price_per_share: 13, effective_date: "2026-07-01", source: "tender" },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      delete "/api/v1/equity/fmv_entries/#{entry_id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(EquityFmvEntry.count).to eq(0)
    end
  end

  describe "grants" do
    let(:company) { create(:equity_company) }

    it "creates a grant with a custom schedule" do
      post "/api/v1/equity/grants",
           params: { equity_company_id: company.id, label: "RSU-1", grant_type: "rsu",
                     grant_date: "2025-05-15", quantity: 1000, double_trigger: true,
                     custom_tranches: [
                       { date: "2026-05-15", quantity: 50 },
                       { date: "2027-05-15", quantity: 150 }
                     ] },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include("label" => "RSU-1", "grant_type" => "rsu", "double_trigger" => true,
                              "vesting_commencement_date" => "2025-05-15", "vested_quantity" => 50.0)
      expect(body["tranches"]).to eq([
        { "date" => "2026-05-15", "quantity" => 50.0, "vested" => true },
        { "date" => "2027-05-15", "quantity" => 150.0, "vested" => false }
      ])
    end

    it "rejects an option grant without a strike" do
      post "/api/v1/equity/grants",
           params: { equity_company_id: company.id, grant_type: "iso", grant_date: "2026-01-01",
                     quantity: 100, vesting_interval: "monthly", vesting_occurrences: 12 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/strike price/i)
    end

    it "updates and deletes a grant" do
      grant = create(:equity_grant, equity_company: company)

      patch "/api/v1/equity/grants/#{grant.id}",
            params: { label: "Refresh" }, headers: auth_headers, as: :json
      expect(response.parsed_body["label"]).to eq("Refresh")

      delete "/api/v1/equity/grants/#{grant.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(EquityGrant.count).to eq(0)
    end
  end

  describe "events" do
    let(:grant) do
      create(:equity_grant, quantity: 100, grant_date: Date.current - 7.months,
             vesting_interval: "quarterly", vesting_occurrences: 4, cliff_installments: 0)
    end

    it "creates and deletes events" do
      post "/api/v1/equity/grants/#{grant.id}/events",
           params: { kind: "exercise", occurred_on: Date.current.iso8601, quantity: 30,
                     share_price: 9.5, method: "sell_to_cover", shares_withheld: 5 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include("kind" => "exercise", "quantity" => 30.0, "share_price" => 9.5,
                              "method" => "sell_to_cover", "shares_withheld" => 5.0,
                              "election_83b" => false)

      delete "/api/v1/equity/events/#{body['id']}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(EquityGrantEvent.count).to eq(0)
    end

    it "rejects exercising beyond vested with a 422" do
      post "/api/v1/equity/grants/#{grant.id}/events",
           params: { kind: "exercise", occurred_on: Date.current.iso8601, quantity: 80 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/exceeds vested shares/)
    end
  end

  describe "POST /api/v1/equity/grants/:id/exercise_plan" do
    let(:company) { create(:equity_company) }
    let(:grant) do
      create(:equity_grant, :fully_vested, equity_company: company, grant_type: "iso",
             strike_price: 2, quantity: 20_000, grant_date: Date.current - 2.years)
    end

    before do
      create(:equity_fmv_entry, equity_company: company, price_per_share: 22,
             effective_date: Date.current - 1.month)
    end

    it "returns the full plan for the crossover quantity by default" do
      create(:tax_profile, tax_year: Date.current.year, filing_status: "mfj",
             projected_wages: 332_200)

      post "/api/v1/equity/grants/#{grant.id}/exercise_plan", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("tax_year" => Date.current.year, "share_price" => 22.0,
                              "strike_price" => 2.0, "exercisable_quantity" => 20_000.0,
                              "escape_hatch_deadline" => "#{Date.current.year}-12-31")
      expect(body["figures_status"]).to eq("federal" => "final", "state" => "projected")

      expect(body["crossover"]).to include("shares" => 1_399, "binding" => "federal")
      expect(body["crossover"]["spread"]).to be_within(50).of(27_985)

      expect(body["simulation"]).to include("quantity" => 1_399.0)
      expect(body["simulation"]["federal_amt"]).to eq(0.0)
      expect(body["curve"].length).to eq(41)
      expect(body["scenarios"].keys).to match_array(%w[hold same_year_sale qualifying_sale])
      expect(body["safe_harbor"].keys).to match_array(%w[federal california])
      expect(body["stress"]).to include("drop_pct" => 60)
      expect(body["nso_gap"]).to be_nil
      expect(body["exclusions"]).to include("Net investment income tax (3.8%)")
      expect(body["profile"]).to include("complete" => true, "filing_status" => "mfj")
    end

    it "honors a quantity override and stress drop" do
      create(:tax_profile, tax_year: Date.current.year, projected_wages: 400_000)

      post "/api/v1/equity/grants/#{grant.id}/exercise_plan",
           params: { quantity: 5_000, stress_drop_pct: 80 }, headers: auth_headers, as: :json

      body = response.parsed_body
      expect(body["simulation"]["quantity"]).to eq(5_000.0)
      expect(body["stress"]).to include("drop_pct" => 80, "price_after" => 4.4)
    end

    it "returns the NSO gap and no crossover for NSO grants" do
      create(:tax_profile, tax_year: Date.current.year, projected_wages: 400_000)
      nso = create(:equity_grant, :fully_vested, equity_company: company, grant_type: "nso",
                   strike_price: 2, quantity: 1_000, grant_date: Date.current - 2.years)

      post "/api/v1/equity/grants/#{nso.id}/exercise_plan", headers: auth_headers, as: :json

      body = response.parsed_body
      expect(body["crossover"]).to be_nil
      expect(body["nso_gap"]).to include("federal_withholding_rate" => 0.22,
                                         "california_withholding_rate" => 0.1023)
      expect(body["scenarios"].keys).to eq([ "exercise" ])
    end

    it "rejects RSU grants with 422" do
      create(:tax_profile, tax_year: Date.current.year, projected_wages: 400_000)
      rsu = create(:equity_grant, :rsu, :fully_vested, equity_company: company,
                   quantity: 100, grant_date: Date.current - 1.year)

      post "/api/v1/equity/grants/#{rsu.id}/exercise_plan", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/option grants/i)
    end

    it "rejects a grant with no share value with 422" do
      create(:tax_profile, tax_year: Date.current.year, projected_wages: 400_000)
      unpriced = create(:equity_company)
      grant = create(:equity_grant, :fully_vested, equity_company: unpriced, grant_type: "iso",
                     strike_price: 2, quantity: 100, grant_date: Date.current - 1.year)

      post "/api/v1/equity/grants/#{grant.id}/exercise_plan", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("no share value")
    end

    it "rejects a missing tax profile with tax_profile_incomplete" do
      post "/api/v1/equity/grants/#{grant.id}/exercise_plan", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("tax_profile_incomplete")
    end

    it "rejects an incomplete tax profile (no projected wages)" do
      create(:tax_profile, tax_year: Date.current.year, projected_wages: 0)

      post "/api/v1/equity/grants/#{grant.id}/exercise_plan", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("tax_profile_incomplete")
    end
  end

  describe "household isolation" do
    it "hides and protects another household's equity data" do
      company = create(:equity_company, name: "Mine")
      grant = create(:equity_grant, equity_company: company)

      other_household = create(:household)
      other_user      = create(:user)
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)
      other_headers = { "Authorization" => "Bearer #{other_token.raw_token}" }

      get "/api/v1/equity/summary", headers: other_headers
      expect(response.parsed_body["companies"]).to be_empty

      patch "/api/v1/equity/companies/#{company.id}",
            params: { name: "hijack" }, headers: other_headers, as: :json
      expect(response).to have_http_status(:not_found)

      delete "/api/v1/equity/grants/#{grant.id}", headers: other_headers
      expect(response).to have_http_status(:not_found)

      post "/api/v1/equity/grants/#{grant.id}/events",
           params: { kind: "cancellation", occurred_on: Date.current.iso8601, quantity: 1 },
           headers: other_headers, as: :json
      expect(response).to have_http_status(:not_found)

      post "/api/v1/equity/grants/#{grant.id}/exercise_plan", headers: other_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
