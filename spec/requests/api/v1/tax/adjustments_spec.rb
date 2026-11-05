require "rails_helper"

RSpec.describe "Api::V1::Tax::Adjustments", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/tax/adjustments" do
    it "creates an adjustment" do
      post "/api/v1/tax/adjustments",
           params: { tax_year: 2026, kind: "income", jurisdiction: "both",
                     label: "Rental income", amount: 24_000, notes: "Schedule E" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "kind" => "income", "jurisdiction" => "both", "label" => "Rental income", "amount" => 24_000.0
      )
    end

    it "creates a contribution adjustment with a bucket" do
      post "/api/v1/tax/adjustments",
           params: { tax_year: 2026, kind: "contribution", label: "Payroll 401k",
                     amount: 12_000, bucket: "401k" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["bucket"]).to eq("401k")
    end

    it "rejects a bucket on a non-contribution kind and unknown kinds" do
      post "/api/v1/tax/adjustments",
           params: { tax_year: 2026, kind: "income", label: "Oops", amount: 1, bucket: "401k" },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/v1/tax/adjustments",
           params: { tax_year: 2026, kind: "windfall", label: "Oops", amount: 1 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/tax/adjustments/:id" do
    it "updates fields" do
      adjustment = create(:tax_adjustment, amount: 100)

      patch "/api/v1/tax/adjustments/#{adjustment.id}", params: { amount: 250, label: "K-1 revised" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(adjustment.reload).to have_attributes(amount: 250, label: "K-1 revised")
    end
  end

  describe "DELETE /api/v1/tax/adjustments/:id" do
    it "deletes an adjustment and hides other households'" do
      adjustment = create(:tax_adjustment)

      other_household = create(:household)
      other_user      = create(:user, email: "other@example.com")
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)

      delete "/api/v1/tax/adjustments/#{adjustment.id}",
             headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
      expect(response).to have_http_status(:not_found)

      delete "/api/v1/tax/adjustments/#{adjustment.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(TaxAdjustment.unscoped.count).to eq(0)
    end
  end
end
