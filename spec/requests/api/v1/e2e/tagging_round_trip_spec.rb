require "rails_helper"

# E2E flow: a user creates a tag, attaches it to a cash transaction via
# the /add_tag endpoint, then verifies the tag's detail page lists the
# transaction, and removal round-trips cleanly.
RSpec.describe "E2E: tagging round-trip", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account) }
  let!(:txn) do
    # Tag.show only counts source=credit_card transactions, so use that here.
    create(:cash_transaction, :credit_card, account: account, description: "STARBUCKS",
           transaction_type: "Sale", amount: -7.25,
           transaction_date: Date.new(2026, 1, 15))
  end

  describe "via /cash_transactions/:id/add_tag" do
    it "creates a tag, attaches it, surfaces it under /tags/:id, then removes it" do
      post "/api/v1/tags", params: { name: "Coffee" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:created)
      tag_id = response.parsed_body["id"]

      post "/api/v1/cash_transactions/#{txn.id}/add_tag",
           params: { tag_id: tag_id }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tags"].map { |t| t["id"] }).to include(tag_id)
      expect(txn.reload.tags.map(&:id)).to include(tag_id)

      get "/api/v1/tags/#{tag_id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["total_count"]).to eq(1)
      expect(body["total_spend"]).to eq(7.25)

      delete "/api/v1/cash_transactions/#{txn.id}/remove_tag",
             params: { tag_id: tag_id }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(txn.reload.tags).to be_empty

      get "/api/v1/tags/#{tag_id}", headers: auth_headers
      expect(response.parsed_body["total_count"]).to eq(0)
    end

    it "is idempotent — re-tagging does not create duplicate join rows" do
      tag = create(:tag, name: "Once")
      2.times do
        post "/api/v1/cash_transactions/#{txn.id}/add_tag",
             params: { tag_id: tag.id }, headers: auth_headers, as: :json
        expect(response).to have_http_status(:ok)
      end
      expect(CashTransactionTag.where(cash_transaction_id: txn.id, tag_id: tag.id).count).to eq(1)
    end
  end

  describe "tag lifecycle" do
    it "destroys a tag (and its taggings) when deleted" do
      tag = create(:tag, name: "Doomed")
      txn.tags << tag
      delete "/api/v1/tags/#{tag.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(Tag.exists?(tag.id)).to be false
      expect(CashTransactionTag.where(tag_id: tag.id)).to be_empty
    end
  end
end
