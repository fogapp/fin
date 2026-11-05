require "rails_helper"

RSpec.describe "Api::V1::SecurityConversions", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:smney)        { create(:security, ticker: "SMNEY", name: "Siemens Energy Ag-Unsp") }
  let(:smery)        { create(:security, ticker: "SMERY", name: "Siemens Energy AG - ADR - Sponsored") }
  let(:other)        { create(:security, ticker: "VTI") }

  def suggestion!(from: smney, to: smery)
    SecurityConversion.create!(from_security: from, to_security: to, effective_date: Date.new(2026, 1, 30),
                               ratio: 5, evidence: { "account_name" => "Global" })
  end

  it "returns 401 without authentication" do
    get "/api/v1/security_conversions"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /security_conversions" do
    it "lists conversions, filterable by status and by either security" do
      suggested = suggestion!
      confirmed = suggestion!(from: other, to: smery).tap(&:confirm!)

      get "/api/v1/security_conversions", headers: auth_headers
      expect(response.parsed_body.map { |c| c["id"] }).to contain_exactly(suggested.id, confirmed.id)

      get "/api/v1/security_conversions", params: { status: "confirmed" }, headers: auth_headers
      expect(response.parsed_body.map { |c| c["id"] }).to eq([ confirmed.id ])

      get "/api/v1/security_conversions", params: { security_id: smney.id }, headers: auth_headers
      body = response.parsed_body
      expect(body.map { |c| c["id"] }).to eq([ suggested.id ])
      expect(body.first).to include(
        "ratio" => 5.0, "status" => "suggested", "source" => "detected", "effective_date" => "2026-01-30",
        "from_security" => { "id" => smney.id, "ticker" => "SMNEY", "name" => "Siemens Energy Ag-Unsp" }
      )
    end
  end

  describe "POST /security_conversions" do
    it "records a manual conversion as confirmed and recomputes the portfolio metric" do
      expect {
        post "/api/v1/security_conversions", headers: auth_headers,
             params: { from_security_id: smney.id, to_security_id: smery.id, effective_date: "2026-01-30", ratio: "5" }
      }.to have_enqueued_job(Metrics::BackfillJob)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("status" => "confirmed", "source" => "manual", "ratio" => 5.0)
      expect(response.parsed_body["confirmed_at"]).to be_present
    end

    it "rejects a conversion into the same security" do
      post "/api/v1/security_conversions", headers: auth_headers,
           params: { from_security_id: smney.id, to_security_id: smney.id, effective_date: "2026-01-30", ratio: "1" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a malformed date" do
      post "/api/v1/security_conversions", headers: auth_headers,
           params: { from_security_id: smney.id, to_security_id: smery.id, effective_date: "not-a-date", ratio: "1" }
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "confirm / dismiss / delete" do
    it "confirms a suggestion and resolves its issue" do
      conversion = suggestion!
      conversion.raise_issue!

      post "/api/v1/security_conversions/#{conversion.id}/confirm", headers: auth_headers

      expect(response.parsed_body["status"]).to eq("confirmed")
      expect(Issue.active.where(key: conversion.issue_key)).to be_empty
    end

    it "dismisses a suggestion and resolves its issue" do
      conversion = suggestion!
      conversion.raise_issue!

      post "/api/v1/security_conversions/#{conversion.id}/dismiss", headers: auth_headers

      expect(response.parsed_body["status"]).to eq("dismissed")
      expect(Issue.active.where(key: conversion.issue_key)).to be_empty
    end

    it "deletes a confirmed conversion and recomputes the portfolio metric" do
      conversion = suggestion!.tap(&:confirm!)

      expect {
        delete "/api/v1/security_conversions/#{conversion.id}", headers: auth_headers
      }.to have_enqueued_job(Metrics::BackfillJob)

      expect(response).to have_http_status(:no_content)
      expect(SecurityConversion.exists?(conversion.id)).to be(false)
    end

    it "bumps the household data version so cached valuations refresh" do
      conversion = suggestion!
      expect(Households::DataVersion).to receive(:bump_coalesced!).at_least(:once)

      post "/api/v1/security_conversions/#{conversion.id}/confirm", headers: auth_headers
    end
  end
end
