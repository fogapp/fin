require "rails_helper"

RSpec.describe "Api::V1::SecurityLabels", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:household)    { token.household }
  let(:security)     { create(:security, ticker: "VMFXX", name: "Vanguard Federal MMF") }

  describe "PATCH /api/v1/security_labels/:security_id" do
    it "creates a label for the household" do
      expect {
        patch "/api/v1/security_labels/#{security.id}",
              params: { label: "  Emergency fund  " }, headers: auth_headers, as: :json
      }.to change(SecurityLabel, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("security_id" => security.id, "label" => "Emergency fund")

      label = SecurityLabel.unscoped.find_by(security: security)
      expect(label.label).to eq("Emergency fund")
      expect(label.household_id).to eq(household.id)
    end

    it "updates the existing label instead of adding a second one" do
      create(:security_label, security: security, household: household, label: "Old")

      expect {
        patch "/api/v1/security_labels/#{security.id}",
              params: { label: "New" }, headers: auth_headers, as: :json
      }.not_to change(SecurityLabel, :count)

      expect(SecurityLabel.unscoped.find_by(security: security).label).to eq("New")
    end

    it "is idempotent when the same label is sent twice" do
      2.times do
        patch "/api/v1/security_labels/#{security.id}",
              params: { label: "Emergency fund" }, headers: auth_headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      expect(SecurityLabel.unscoped.where(security: security).count).to eq(1)
    end

    it "settles rather than 409s when a concurrent request already inserted the row" do
      # Stand in for the losing side of the race: the row appears between this
      # request's find_or_initialize_by and its INSERT.
      allow(SecurityLabel).to receive(:find_or_initialize_by).and_wrap_original do |orig, *args|
        create(:security_label, security: security, household: household, label: "Winner")
        orig.call(*args)
      end

      patch "/api/v1/security_labels/#{security.id}",
            params: { label: "Mine" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(SecurityLabel.unscoped.where(security: security).pluck(:label)).to eq([ "Mine" ])
    end

    it "clears the label when a blank value is sent" do
      create(:security_label, security: security, household: household, label: "Old")

      expect {
        patch "/api/v1/security_labels/#{security.id}",
              params: { label: "   " }, headers: auth_headers, as: :json
      }.to change(SecurityLabel, :count).by(-1)

      expect(response.parsed_body).to eq("security_id" => security.id, "label" => nil)
    end

    it "leaves another household's label for the same security alone" do
      other = create(:security_label, security: security, household: create(:household), label: "Theirs")

      patch "/api/v1/security_labels/#{security.id}",
            params: { label: "Mine" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(other.reload.label).to eq("Theirs")
      expect(SecurityLabel.unscoped.where(security: security).count).to eq(2)
    end
  end

  describe "labels in holdings payloads" do
    it "ships the label, cusip, and security_id with each portfolio position" do
      account = create(:account)
      create(:position_snapshot, account: account, security: security,
                                 as_of_date: Date.current, quantity: 10, price: 1, market_value: 10)
      create(:security_label, security: security, household: household, label: "Emergency fund")

      get "/api/v1/portfolio", headers: auth_headers
      expect(response).to have_http_status(:ok)

      position = response.parsed_body["positions"].find { |p| p["security_id"] == security.id }
      expect(position).to include(
        "security_label"  => "Emergency fund",
        "security_cusip"  => security.cusip,
        "security_ticker" => "VMFXX"
      )
    end
  end
end
