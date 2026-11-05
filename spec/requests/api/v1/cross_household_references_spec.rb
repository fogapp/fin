require "rails_helper"

# Write-side tenancy guardrail. HouseholdScoped's default_scope hides other
# households' rows from reads, but a foreign key assigned from params is never
# loaded through it — before the reference check, a household could save
# `account_id: <another household's account>` on its own records. Every write
# that takes a household-scoped id must reject one from another household and
# leave the record untouched.
RSpec.describe "Cross-household references", type: :request do
  let(:token)   { create(:api_token) } # household A, the spec-wide Current.household
  let(:headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  let(:household_b) { create(:household, name: "Other Household") }
  let(:foreign) do
    Current.set(household: household_b) do
      {
        account:  create(:account, name: "B's account"),
        merchant: create(:merchant, name: "B's merchant"),
        category: create(:category, name: "B's category"),
        loan:     create(:loan, name: "B's loan"),
        tag:      create(:tag, name: "B's tag")
      }
    end
  end

  describe "cash transactions" do
    let(:account) { create(:account) }
    let(:txn)     { create(:cash_transaction, :bank, account: account) }

    it "404s a create that names another household's account, creating nothing" do
      expect {
        post "/api/v1/cash_transactions",
             params: { source: "bank", transaction_date: Date.current, description: "x", amount: -5,
                       account_id: foreign[:account].id },
             headers: headers, as: :json
      }.not_to change(CashTransaction.unscoped, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s an update that moves a transaction into another household's account" do
      patch "/api/v1/cash_transactions/#{txn.id}", params: { account_id: foreign[:account].id },
                                                   headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(txn.reload.account_id).to eq(account.id)
    end

    %i[merchant category loan].each do |kind|
      it "rejects another household's #{kind} with 422 and keeps the row unchanged" do
        patch "/api/v1/cash_transactions/#{txn.id}", params: { "#{kind}_id" => foreign[kind].id },
                                                     headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to include(a_string_matching(/must belong to this household/))
        expect(txn.reload.public_send("#{kind}_id")).to be_nil
      end
    end

    it "still links and unlinks the household's own records" do
      own_account = create(:account)
      merchant    = create(:merchant)

      patch "/api/v1/cash_transactions/#{txn.id}", params: { account_id: own_account.id, merchant_id: merchant.id },
                                                   headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(txn.reload).to have_attributes(account_id: own_account.id, merchant_id: merchant.id)

      patch "/api/v1/cash_transactions/#{txn.id}", params: { account_id: nil }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(txn.reload.account_id).to be_nil
    end

    it "404s a bulk update tagging with another household's tag, linking nothing" do
      post "/api/v1/cash_transactions/bulk_update",
           params: { ids: [ txn.id ], tag_ids: [ foreign[:tag].id ] }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(CashTransactionTag.where(cash_transaction_id: txn.id)).to be_empty
    end
  end

  describe "loans" do
    let(:loan) { create(:loan) }

    it "404s another household's account" do
      patch "/api/v1/loans/#{loan.id}", params: { account_id: foreign[:account].id }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(loan.reload.account_id).to be_nil
    end

    it "rejects another household's merchant" do
      patch "/api/v1/loans/#{loan.id}", params: { merchant_id: foreign[:merchant].id }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(loan.reload.merchant_id).to be_nil
    end
  end

  describe "subscriptions" do
    let(:series) { create(:recurring_series, :active) }

    it "404s another household's account" do
      patch "/api/v1/subscriptions/#{series.id}", params: { account_id: foreign[:account].id },
                                                  headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(series.reload.account_id).to be_nil
    end

    it "rejects another household's merchant" do
      patch "/api/v1/subscriptions/#{series.id}", params: { merchant_id: foreign[:merchant].id },
                                                  headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(series.reload.merchant_id).to be_nil
    end
  end

  it "404s an Alchemy wallet linked to another household's account" do
    wallet = create(:alchemy_wallet)

    patch "/api/v1/alchemy/wallets/#{wallet.id}",
          params: { alchemy_wallet: { account_id: foreign[:account].id } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(wallet.reload.account_id).to be_nil
  end

  it "404s an investment lot moved into another household's account" do
    lot = create(:investment_lot)

    patch "/api/v1/investment_lots/#{lot.id}", params: { account_id: foreign[:account].id },
                                               headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(lot.reload.account.household_id).to eq(Current.household.id)
  end
end
