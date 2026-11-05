require "rails_helper"

RSpec.describe "Api::V1::CashTransactions filter", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/cash_transactions/filter" do
    it "returns 401 without authentication" do
      post "/api/v1/cash_transactions/filter", params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "with valid token" do
      it "returns 200 with empty array when no transactions exist" do
        post "/api/v1/cash_transactions/filter", params: { conditions: [] },
             headers: auth_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end

      it "returns all transactions with empty conditions" do
        create(:cash_transaction, :credit_card, :sale)
        create(:cash_transaction, :bank, :debit)

        post "/api/v1/cash_transactions/filter", params: { conditions: [] },
             headers: auth_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "returns all transactions when conditions param is omitted" do
        create(:cash_transaction, :credit_card, :sale)

        post "/api/v1/cash_transactions/filter", params: {},
             headers: auth_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
      end

      it "filters transactions using conditions" do
        create(:cash_transaction, :credit_card, :sale, description: "AMAZON.COM")
        create(:cash_transaction, :credit_card, :sale, description: "NETFLIX")

        post "/api/v1/cash_transactions/filter",
             params: {
               conditions: [ { field: "description", operator: "contains", value: "AMAZON" } ],
               match_all:  true
             },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first["description"]).to eq("AMAZON.COM")
      end

      it "respects match_all false (OR logic)" do
        create(:cash_transaction, :credit_card, :sale, description: "AMAZON.COM")
        create(:cash_transaction, :credit_card, :sale, description: "NETFLIX")
        create(:cash_transaction, :credit_card, :sale, description: "SPOTIFY")

        post "/api/v1/cash_transactions/filter",
             params: {
               conditions: [
                 { field: "description", operator: "contains", value: "AMAZON" },
                 { field: "description", operator: "contains", value: "NETFLIX" }
               ],
               match_all: false
             },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "respects the limit param with empty conditions" do
        create_list(:cash_transaction, 5, :credit_card, :sale)

        post "/api/v1/cash_transactions/filter",
             params: { conditions: [], limit: 2 },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "preloads every association the row serializer reads" do
        parent = create(:category, name: "Home")
        loan   = create(:loan)
        4.times do
          create(:cash_transaction, :credit_card, :sale,
                 category: create(:category, parent: parent), loan: loan)
        end
        a = create(:cash_transaction, :bank, :debit)
        b = create(:cash_transaction, :bank, :credit)
        create(:transfer, from_transaction_id: a.id, from_transaction_type: "CashTransaction",
                          to_transaction_id: b.id, to_transaction_type: "CashTransaction").sync_transfer_ids

        queries = count_queries do
          post "/api/v1/cash_transactions/filter", params: { conditions: [] },
               headers: auth_headers, as: :json
        end

        expect(response.parsed_body.length).to eq(6)
        # One preload per association, not one lazy load per row.
        expect(queries.grep(/FROM "categories"/).size).to be <= 2
        expect(queries.grep(/FROM "loans"/).size).to eq(1)
        expect(queries.grep(/FROM "transfers"/).size).to eq(1)
      end

      it "clamps a negative limit instead of erroring" do
        create_list(:cash_transaction, 2, :credit_card, :sale)

        post "/api/v1/cash_transactions/filter", params: { conditions: [], limit: -5 },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
      end

      it "applies a server-side default limit when the client omits one" do
        stub_const("Api::Render::CashTransaction::FILTER_DEFAULT_LIMIT", 2)
        create_list(:cash_transaction, 3, :credit_card, :sale)

        post "/api/v1/cash_transactions/filter", params: { conditions: [] },
             headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "clamps the limit param to the server-side maximum" do
        stub_const("Api::Render::CashTransaction::FILTER_MAX_LIMIT", 2)
        create_list(:cash_transaction, 3, :credit_card, :sale)

        post "/api/v1/cash_transactions/filter", params: { conditions: [], limit: 999 },
             headers: auth_headers, as: :json

        expect(response.parsed_body.length).to eq(2)
      end

      it "returns transactions as an array" do
        post "/api/v1/cash_transactions/filter", params: { conditions: [] },
             headers: auth_headers, as: :json
        expect(response.parsed_body).to be_an(Array)
      end
    end
  end

  it "returns a sample plus total when count is requested" do
    create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS 001")
    create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS 002")
    create(:cash_transaction, :credit_card, :sale, description: "GROCERY")

    post "/api/v1/cash_transactions/filter",
         params: { conditions: [ { field: "description", operator: "contains", value: "STARBUCKS" } ],
                   limit: 1, count: true },
         headers: auth_headers, as: :json

    body = response.parsed_body
    expect(body["transactions"].size).to eq(1)
    expect(body["total"]).to eq(2)
  end
end
