require "rails_helper"

RSpec.describe "Api::V1::Tax::ChecklistItems", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/tax/checklist_items" do
    it "creates a user-added item defaulting to expected" do
      post "/api/v1/tax/checklist_items",
           params: { tax_year: 2026, kind: "k1", source_label: "Family LP" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "kind" => "k1", "source_label" => "Family LP", "status" => "expected", "auto_seeded" => false
      )
    end

    it "rejects duplicates of the same (year, kind, source)" do
      create(:tax_checklist_item, tax_year: 2026, kind: "k1", source_label: "Family LP")

      post "/api/v1/tax/checklist_items",
           params: { tax_year: 2026, kind: "k1", source_label: "Family LP" },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/tax/checklist_items/:id" do
    it "updates status" do
      item = create(:tax_checklist_item, status: "expected")

      patch "/api/v1/tax/checklist_items/#{item.id}", params: { status: "received" },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(item.reload.status).to eq(TaxChecklistItem::Status::Received)
    end

    it "rejects unknown statuses" do
      item = create(:tax_checklist_item)

      patch "/api/v1/tax/checklist_items/#{item.id}", params: { status: "lost" },
            headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/tax/checklist_items/:id" do
    it "deletes user-added items" do
      item = create(:tax_checklist_item)

      delete "/api/v1/tax/checklist_items/#{item.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(TaxChecklistItem.count).to eq(0)
    end

    it "refuses to delete auto-seeded items with a 422" do
      item = create(:tax_checklist_item, :seeded)

      delete "/api/v1/tax/checklist_items/#{item.id}", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("auto-seeded items cannot be deleted; mark n_a instead")
      expect(TaxChecklistItem.count).to eq(1)
    end

    it "hides other households' items" do
      item = create(:tax_checklist_item)

      other_household = create(:household)
      other_user      = create(:user, email: "other@example.com")
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)

      delete "/api/v1/tax/checklist_items/#{item.id}",
             headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
