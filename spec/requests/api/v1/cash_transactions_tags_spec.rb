require "rails_helper"

RSpec.describe "Api::V1::CashTransactions tags", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/cash_transactions/:id/add_tag" do
    let!(:txn) { create(:cash_transaction, :credit_card, :sale) }
    let!(:tag) { create(:tag, name: "travel") }

    it "returns 401 without authentication" do
      post "/api/v1/cash_transactions/#{txn.id}/add_tag", params: { tag_id: tag.id }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "adds the tag to the transaction and returns the updated transaction" do
      post "/api/v1/cash_transactions/#{txn.id}/add_tag",
           params: { tag_id: tag.id },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(txn.id)
      expect(txn.reload.tags.map(&:name)).to include("travel")
    end

    it "does not duplicate a tag already present" do
      txn.tags << tag

      expect {
        post "/api/v1/cash_transactions/#{txn.id}/add_tag",
             params: { tag_id: tag.id },
             headers: auth_headers, as: :json
      }.not_to change { txn.reload.tags.count }

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a missing transaction" do
      post "/api/v1/cash_transactions/0/add_tag",
           params: { tag_id: tag.id },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a missing tag" do
      post "/api/v1/cash_transactions/#{txn.id}/add_tag",
           params: { tag_id: 0 },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/cash_transactions/:id/remove_tag" do
    let!(:txn) { create(:cash_transaction, :credit_card, :sale) }
    let!(:tag) { create(:tag, name: "food") }

    before { txn.tags << tag }

    it "returns 401 without authentication" do
      delete "/api/v1/cash_transactions/#{txn.id}/remove_tag", params: { tag_id: tag.id }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "removes the tag from the transaction and returns the updated transaction" do
      delete "/api/v1/cash_transactions/#{txn.id}/remove_tag",
             params: { tag_id: tag.id },
             headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(txn.id)
      expect(txn.reload.tags).not_to include(tag)
    end

    it "returns 404 for a missing transaction" do
      delete "/api/v1/cash_transactions/0/remove_tag",
             params: { tag_id: tag.id },
             headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a missing tag" do
      delete "/api/v1/cash_transactions/#{txn.id}/remove_tag",
             params: { tag_id: 0 },
             headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
