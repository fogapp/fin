require "rails_helper"

RSpec.describe "Api::V1::Tax::EstimatedPayments", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/tax/estimated_payments" do
    it "records a payment and derives its quarter" do
      post "/api/v1/tax/estimated_payments",
           params: { tax_year: 2026, jurisdiction: "state", paid_on: "2026-06-01",
                     amount: 3_000, notes: "FTB Web Pay" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "jurisdiction" => "state", "amount" => 3_000.0, "quarter" => "Q2", "notes" => "FTB Web Pay"
      )
      expect(EstimatedTaxPayment.sole.household).to eq(Current.household)
    end

    it "rejects invalid payments" do
      post "/api/v1/tax/estimated_payments",
           params: { tax_year: 2026, jurisdiction: "city", paid_on: "2026-06-01", amount: 100 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/v1/tax/estimated_payments",
           params: { tax_year: 2026, jurisdiction: "federal", paid_on: "2026-06-01", amount: -1 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/tax/estimated_payments/:id" do
    it "deletes a payment" do
      payment = create(:estimated_tax_payment)

      delete "/api/v1/tax/estimated_payments/#{payment.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(EstimatedTaxPayment.count).to eq(0)
    end

    it "hides other households' payments" do
      payment = create(:estimated_tax_payment)

      other_household = create(:household)
      other_user      = create(:user, email: "other@example.com")
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)

      delete "/api/v1/tax/estimated_payments/#{payment.id}",
             headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
      expect(response).to have_http_status(:not_found)
      expect(EstimatedTaxPayment.unscoped.count).to eq(1)
    end
  end
end
