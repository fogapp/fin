require "rails_helper"

RSpec.describe "Api::V1::CashTransactions", type: :request do
  let(:token) { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/cash_transactions" do
    context "without authentication" do
      it "returns 401" do
        get "/api/v1/cash_transactions"
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to be_present
      end
    end

    context "with invalid token" do
      it "returns 401" do
        get "/api/v1/cash_transactions", headers: { "Authorization" => "Bearer badtoken" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with expired token" do
      it "returns 401" do
        expired = create(:api_token, :expired)
        get "/api/v1/cash_transactions", headers: { "Authorization" => "Bearer #{expired.raw_token}" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "returns 200 with empty array when no transactions" do
        get "/api/v1/cash_transactions", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end

      it "clamps negative limit and offset instead of erroring" do
        create_list(:cash_transaction, 2, :bank, :debit)

        get "/api/v1/cash_transactions", params: { limit: -1, offset: -1 }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
      end

      it "returns all transactions" do
        create(:cash_transaction, :bank, :debit)
        create(:cash_transaction, :credit_card, :sale)

        get "/api/v1/cash_transactions", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(2)
      end

      it "filters by source" do
        create(:cash_transaction, :bank, :debit)
        create(:cash_transaction, :credit_card, :sale)

        get "/api/v1/cash_transactions", params: { source: "bank" }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first["source"]).to eq("bank")
      end

      it "filters by description" do
        create(:cash_transaction, :bank, :debit, description: "COSTCO WHOLESALE")
        create(:cash_transaction, :bank, :debit, description: "SAFEWAY")

        get "/api/v1/cash_transactions", params: { description: "COSTCO" }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first["description"]).to eq("COSTCO WHOLESALE")
      end

      # % and _ are LIKE wildcards. Unescaped, "50%" became the pattern
      # %50%% — matching any description merely containing "50" — so the
      # filter silently over-matched whenever the user's text held one.
      it "treats LIKE wildcards in the description filter as literal text" do
        create(:cash_transaction, :bank, :debit, description: "50% off coupon")
        create(:cash_transaction, :bank, :debit, description: "5000 DEPOSIT")

        get "/api/v1/cash_transactions", params: { description: "50%" }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["description"] }).to eq([ "50% off coupon" ])
      end

      it "treats an underscore in the description filter as literal text" do
        create(:cash_transaction, :bank, :debit, description: "REF_1234")
        create(:cash_transaction, :bank, :debit, description: "REFX1234")

        get "/api/v1/cash_transactions", params: { description: "REF_1" }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["description"] }).to eq([ "REF_1234" ])
      end

      it "filters by start_date" do
        create(:cash_transaction, :bank, :debit, transaction_date: 10.days.ago)
        recent = create(:cash_transaction, :bank, :credit, transaction_date: 2.days.ago)

        get "/api/v1/cash_transactions", params: { start_date: 5.days.ago.to_date.to_s }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(recent.id)
      end

      it "filters by end_date" do
        old = create(:cash_transaction, :bank, :debit, transaction_date: 10.days.ago)
        create(:cash_transaction, :bank, :credit, transaction_date: 2.days.ago)

        get "/api/v1/cash_transactions", params: { end_date: 5.days.ago.to_date.to_s }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(old.id)
      end

      it "honors from/to as aliases for start_date/end_date" do
        create(:cash_transaction, :bank, :debit, transaction_date: 10.days.ago)
        mid = create(:cash_transaction, :bank, :credit, transaction_date: 4.days.ago)
        create(:cash_transaction, :bank, :credit, transaction_date: 1.day.ago)

        get "/api/v1/cash_transactions",
            params: { from: 5.days.ago.to_date.to_s, to: 2.days.ago.to_date.to_s },
            headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(mid.id)
      end

      it "rolls a category_id filter up to include the category's children" do
        parent = create(:category)
        child  = create(:category, parent: parent)
        other  = create(:category)
        in_parent = create(:cash_transaction, :bank, :debit, category: parent)
        in_child  = create(:cash_transaction, :bank, :debit, category: child)
        create(:cash_transaction, :bank, :debit, category: other)

        get "/api/v1/cash_transactions", params: { category_id: parent.id }, headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |t| t["id"] }).to contain_exactly(in_parent.id, in_child.id)
      end

      it "drops rows carrying any exclude_tag_ids tag" do
        vacation = create(:tag, name: "vacation")
        party    = create(:tag, name: "party")
        kept     = create(:cash_transaction, :bank, :debit)
        create(:cash_transaction, :bank, :debit).tags << vacation
        create(:cash_transaction, :bank, :debit).tags << party

        get "/api/v1/cash_transactions", params: { exclude_tag_ids: "#{vacation.id},#{party.id}" }, headers: auth_headers
        expect(response.parsed_body.map { |t| t["id"] }).to eq([ kept.id ])
      end

      it "returns transactions sorted by date descending" do
        t1 = create(:cash_transaction, :bank, :debit, transaction_date: 3.days.ago)
        t2 = create(:cash_transaction, :bank, :credit, transaction_date: 1.day.ago)

        get "/api/v1/cash_transactions", headers: auth_headers
        expect(response.parsed_body.map { |t| t["id"] }).to eq([ t2.id, t1.id ])
      end

      it "updates last_used_at on the token" do
        expect { get "/api/v1/cash_transactions", headers: auth_headers }
          .to change { token.reload.last_used_at }
      end
    end
  end

  describe "GET /api/v1/cash_transactions/:id" do
    context "without authentication" do
      it "returns 401" do
        txn = create(:cash_transaction, :bank, :debit)
        get "/api/v1/cash_transactions/#{txn.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "returns the transaction" do
        txn = create(:cash_transaction, :bank, :debit, description: "Test Txn")

        get "/api/v1/cash_transactions/#{txn.id}", headers: auth_headers
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["id"]).to eq(txn.id)
        expect(body["description"]).to eq("Test Txn")
        expect(body["source"]).to eq("bank")
      end

      it "returns 404 for nonexistent id" do
        get "/api/v1/cash_transactions/0", headers: auth_headers
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to be_present
      end
    end
  end

  describe "POST /api/v1/cash_transactions" do
    let(:valid_params) do
      {
        source: "bank",
        transaction_date: "2026-01-15",
        description: "Direct Deposit",
        amount: 2500.00,
        transaction_type: "Credit",
        balance: 3000.00,
        source_row_hash: "unique-hash-abc"
      }
    end

    context "without authentication" do
      it "returns 401" do
        post "/api/v1/cash_transactions", params: valid_params, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "creates and returns the transaction" do
        post "/api/v1/cash_transactions", params: valid_params, headers: auth_headers, as: :json
        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["description"]).to eq("Direct Deposit")
        expect(body["source"]).to eq("bank")
        expect(body["amount"]).to eq(2500.0)
      end

      it "persists the record" do
        expect {
          post "/api/v1/cash_transactions", params: valid_params, headers: auth_headers, as: :json
        }.to change(CashTransaction, :count).by(1)
      end

      it "returns 422 with errors when invalid" do
        post "/api/v1/cash_transactions", params: { source: "bank" }, headers: auth_headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to be_present
      end
    end
  end

  describe "PATCH /api/v1/cash_transactions/:id" do
    context "without authentication" do
      it "returns 401" do
        txn = create(:cash_transaction, :bank, :debit)
        patch "/api/v1/cash_transactions/#{txn.id}", params: { memo: "updated" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "updates and returns the transaction" do
        txn = create(:cash_transaction, :bank, :debit)
        patch "/api/v1/cash_transactions/#{txn.id}",
              params: { memo: "salary", description: "Updated Desc" },
              headers: auth_headers, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["memo"]).to eq("salary")
        expect(body["description"]).to eq("Updated Desc")
      end

      it "excludes a transaction from budgets" do
        txn = create(:cash_transaction, :bank, :debit)
        patch "/api/v1/cash_transactions/#{txn.id}", params: { budget_excluded: true }, headers: auth_headers, as: :json

        expect(response.parsed_body["budget_excluded"]).to be(true)
        expect(txn.reload.budget_excluded).to be(true)
      end

      it "returns 404 for nonexistent id" do
        patch "/api/v1/cash_transactions/0", params: { memo: "x" }, headers: auth_headers, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/cash_transactions/:id" do
    context "without authentication" do
      it "returns 401" do
        txn = create(:cash_transaction, :bank, :debit)
        delete "/api/v1/cash_transactions/#{txn.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with valid token" do
      it "destroys the transaction and returns 204" do
        txn = create(:cash_transaction, :bank, :debit)
        expect {
          delete "/api/v1/cash_transactions/#{txn.id}", headers: auth_headers
        }.to change(CashTransaction, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end

      it "returns 404 for nonexistent id" do
        delete "/api/v1/cash_transactions/0", headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
