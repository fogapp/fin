require "rails_helper"

RSpec.describe "Api::V1::RealEstateProperties", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  def stub_value(price: 912_000)
    stub_request(:get, "https://api.rentcast.io/v1/avm/value")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { price: price }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_record
    stub_request(:get, "https://api.rentcast.io/v1/properties")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { id: "x", formattedAddress: "1 Main St, Austin, TX" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  describe "GET /api/v1/real_estate_properties" do
    it "returns 401 without authentication" do
      get "/api/v1/real_estate_properties"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns properties with totals and the integration state" do
      property = create(:real_estate_property, name: "Primary residence")
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 900_000)

      get "/api/v1/real_estate_properties", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"].first).to include("name" => "Primary residence", "value" => 900_000.0,
                                                  "value_source" => "manual")
      expect(body["totals"]).to include("value" => 900_000.0, "equity" => 900_000.0, "count" => 1)
      expect(body["rentcast"]["configured"]).to be false
    end

    it "doesn't query per property or per linked loan" do
      2.times do |n|
        property = create(:real_estate_property, name: "Property #{n}")
        property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 900_000)
        2.times do
          loan = create(:loan, real_estate_property: property)
          create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.current - 10)
        end
      end

      get "/api/v1/real_estate_properties", headers: auth_headers # warm auth/config lookups
      queries = count_queries { get "/api/v1/real_estate_properties", headers: auth_headers }

      expect(queries.grep(/FROM "cash_transactions"/).size).to eq(1)
      expect(queries.grep(/FROM "loans"/).size).to eq(1)
    end

    it "excludes sold properties from the totals" do
      sold = create(:real_estate_property, status: "sold", sold_date: Date.current, sold_price: 500_000)
      sold.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 500_000)

      get "/api/v1/real_estate_properties", headers: auth_headers

      expect(response.parsed_body["totals"]["count"]).to eq(0)
      expect(response.parsed_body["totals"]["value"]).to eq(0.0)
    end
  end

  describe "POST /api/v1/real_estate_properties" do
    it "creates a property with a manually entered value when RentCast isn't configured" do
      post "/api/v1/real_estate_properties",
           params: { name: "Cabin", address_line1: "1 Main St", value: 300_000 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("name" => "Cabin", "value" => 300_000.0, "value_source" => "manual")
      expect(a_request(:get, /rentcast/)).not_to have_been_made
    end

    it "seeds from RentCast when the integration is configured" do
      create(:rentcast_configuration, api_key: "k")
      stub_record
      stub_value

      post "/api/v1/real_estate_properties",
           params: { name: "House", address_line1: "1 Main St" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["value"]).to eq(912_000.0)
      expect(response.parsed_body["value_source"]).to eq("rentcast")
    end

    it "still creates the property when the RentCast lookup fails" do
      create(:rentcast_configuration, api_key: "k")
      stub_request(:get, %r{https://api\.rentcast\.io/v1/.*}).to_return(status: 500, body: "{}")

      post "/api/v1/real_estate_properties",
           params: { name: "House", address_line1: "1 Main St", value: 400_000 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["value"]).to eq(400_000.0)
      expect(response.parsed_body["last_sync_error"]).to be_present
    end

    it "records the purchase price as the earliest chart point" do
      post "/api/v1/real_estate_properties",
           params: { name: "House", address_line1: "1 Main St", purchase_price: 720_000,
                     purchase_date: "2019-06-01", value: 900_000 },
           headers: auth_headers, as: :json

      id = response.parsed_body["id"]
      get "/api/v1/real_estate_properties/#{id}", headers: auth_headers

      sources = response.parsed_body["valuations"].map { |v| v["source"] }
      expect(sources).to include("purchase", "manual")
    end

    it "rejects a property with no name" do
      post "/api/v1/real_estate_properties",
           params: { address_line1: "1 Main St" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/real_estate_properties/:id" do
    it "returns the valuation history and facts" do
      property = create(:real_estate_property, bedrooms: 3, square_footage: 1878)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)
      property.record_valuation!(source: RealEstateValuation::Source::TaxAssessment,
                                 as_of: Date.new(2024, 12, 31), amount: 648_000)

      get "/api/v1/real_estate_properties/#{property.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["valuations"].length).to eq(2)
      expect(response.parsed_body["facts"]).to include("bedrooms" => 3, "square_footage" => 1878)
    end

    it "returns 404 for an unknown property" do
      get "/api/v1/real_estate_properties/#{SecureRandom.uuid}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "valuations" do
    it "records a manual valuation that beats a same-day estimate" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)

      post "/api/v1/real_estate_properties/#{property.id}/valuations",
           params: { amount: 950_000 }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(property.reload.current_value).to eq(950_000)
    end

    it "accepts a back-dated valuation" do
      property = create(:real_estate_property)

      post "/api/v1/real_estate_properties/#{property.id}/valuations",
           params: { amount: 800_000, as_of: "2024-01-15" }, headers: auth_headers, as: :json

      expect(response.parsed_body["as_of"]).to eq("2024-01-15")
    end

    it "rejects a malformed date with a 400" do
      property = create(:real_estate_property)

      post "/api/v1/real_estate_properties/#{property.id}/valuations",
           params: { amount: 1, as_of: "not-a-date" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "deletes a valuation" do
      property = create(:real_estate_property)
      valuation = property.record_valuation!(source: RealEstateValuation::Source::Manual,
                                             as_of: Date.current, amount: 900_000)

      delete "/api/v1/real_estate_properties/#{property.id}/valuations/#{valuation.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(property.reload.current_value).to be_nil
    end
  end

  describe "POST /api/v1/real_estate_properties/:id/refresh" do
    it "refuses when RentCast isn't configured" do
      property = create(:real_estate_property)

      post "/api/v1/real_estate_properties/#{property.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/not configured/)
    end

    it "refreshes the value" do
      create(:rentcast_configuration, api_key: "k")
      property = create(:real_estate_property, facts_synced_at: Time.current)
      stub_value(price: 999_000)

      post "/api/v1/real_estate_properties/#{property.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["value"]).to eq(999_000.0)
    end

    it "returns a 422 rather than a 500 when the allowance is gone" do
      create(:rentcast_configuration, api_key: "k", requests_used: 50,
                                      quota_period_start: Date.current.beginning_of_month)
      property = create(:real_estate_property, facts_synced_at: Time.current)

      post "/api/v1/real_estate_properties/#{property.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/limit reached/)
    end
  end

  describe "DELETE /api/v1/real_estate_properties/:id" do
    it "deletes the property and its valuations" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 1)

      delete "/api/v1/real_estate_properties/#{property.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(RealEstateProperty.count).to eq(0)
      expect(RealEstateValuation.count).to eq(0)
    end
  end
end
