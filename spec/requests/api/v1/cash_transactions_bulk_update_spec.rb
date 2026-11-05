require "rails_helper"

RSpec.describe "Api::V1::CashTransactions bulk_update", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/cash_transactions/bulk_update" do
    context "without authentication" do
      it "returns 401" do
        post "/api/v1/cash_transactions/bulk_update", params: { ids: [ 1 ] }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      let(:t1) { create(:cash_transaction, :credit_card, :sale) }
      let(:t2) { create(:cash_transaction, :credit_card, :sale) }

      it "returns 400 when ids is missing" do
        post "/api/v1/cash_transactions/bulk_update",
             params: {}, headers: auth_headers, as: :json
        expect(response).to have_http_status(:bad_request)
      end

      it "sets account_id on all specified transactions" do
        account = create(:account)
        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id, t2.id ], account_id: account.id },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["updated"]).to eq(2)
        expect(response.parsed_body["account_id"]).to eq(account.id)
        expect(t1.reload.account_id).to eq(account.id)
        expect(t2.reload.account_id).to eq(account.id)
      end

      it "sets merchant_id and category_id on all specified transactions" do
        merchant = create(:merchant)
        category = create(:category)
        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id, t2.id ], merchant_id: merchant.id, category_id: category.id },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["updated"]).to eq(2)
        expect(response.parsed_body["merchant_id"]).to eq(merchant.id)
        expect(response.parsed_body["category_id"]).to eq(category.id)
        expect(t1.reload.merchant_id).to eq(merchant.id)
        expect(t2.reload.category_id).to eq(category.id)
      end

      it "returns 404 for a nonexistent merchant_id" do
        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id ], merchant_id: "00000000-0000-0000-0000-000000000000" },
             headers: auth_headers, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "adds tags to all specified transactions without duplicating" do
        tag1 = create(:tag)
        tag2 = create(:tag)
        t1.tags << tag1

        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id, t2.id ], tag_ids: [ tag1.id, tag2.id ] },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["tag_ids"]).to match_array([ tag1.id, tag2.id ])
        expect(t1.reload.tags).to match_array([ tag1, tag2 ])
        expect(t2.reload.tags).to match_array([ tag1, tag2 ])
      end

      it "can set account and tags in one request" do
        account = create(:account)
        tag     = create(:tag)

        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id ], account_id: account.id, tag_ids: [ tag.id ] },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(t1.reload.account_id).to eq(account.id)
        expect(t1.reload.tags).to include(tag)
      end

      it "returns 404 for a nonexistent account_id" do
        post "/api/v1/cash_transactions/bulk_update",
             params: { ids: [ t1.id ], account_id: "00000000-0000-0000-0000-000000000000" },
             headers: auth_headers, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
