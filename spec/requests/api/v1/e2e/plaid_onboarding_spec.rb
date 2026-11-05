require "rails_helper"

# E2E flow: a user connects a bank through Plaid Link and sees imported
# transactions. Exercises plaid/link_token → plaid/items create →
# plaid/accounts list → plaid/items/:id/sync → PlaidSyncJob → PlaidSyncer
# → cash_transactions visible.
RSpec.describe "E2E: Plaid onboarding", type: :request do
  let(:token)         { create(:api_token) }
  let(:auth_headers)  { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:plaid_client)  { instance_double(PlaidClient) }

  before do
    allow(PlaidClient).to receive(:new).and_return(plaid_client)

    # Step 1 — link token
    allow(plaid_client).to receive(:create_link_token).and_return(double(link_token: "link-token-xyz"))

    # Step 2 — public-token exchange + initial lookups
    allow(plaid_client).to receive(:exchange_public_token).and_return(
      double(item_id: "item-abc", access_token: "access-abc")
    )
    allow(plaid_client).to receive(:get_item).and_return(
      double(item: double(institution_id: "ins_chase"))
    )
    allow(plaid_client).to receive(:get_institution).and_return(
      double(institution: double(name: "Chase"))
    )

    # Used both at item-create time and during sync_balances
    balances = double(current: 1_200.0, available: 1_100.0, limit: nil,
                      iso_currency_code: "USD", unofficial_currency_code: nil)
    allow(plaid_client).to receive(:get_accounts).and_return(
      double(accounts: [
        double(account_id: "plaid-acct-1", name: "Checking",
               mask: "1234", type: "depository", subtype: "checking",
               balances: balances)
      ])
    )

    # Investment products aren't part of this flow — stub no-ops so the
    # holdings/investment passes at the end of PlaidSyncer#call succeed
    allow(plaid_client).to receive(:get_investment_holdings).and_return(double(holdings: [], securities: []))
    allow(plaid_client).to receive(:get_investment_transactions).and_return(
      double(investment_transactions: [], securities: [], total_investment_transactions: 0)
    )

    # Step 5 — sync returns one added transaction
    plaid_txn = double(
      transaction_id:    "plaid-txn-1",
      account_id:        "plaid-acct-1",
      name:              "Coffee shop",
      amount:            5.25,      # Plaid positive = money leaving (debit)
      date:              Date.new(2026, 1, 15),
      authorized_date:   Date.new(2026, 1, 15),
      personal_finance_category: double(primary: "FOOD_AND_DRINK", detailed: "FOOD_AND_DRINK_COFFEE"),
      payment_channel:   "in store",
      pending:           false,
      pending_transaction_id: nil
    )
    allow(plaid_client).to receive(:sync_transactions).and_return(
      double(added: [ plaid_txn ], modified: [], removed: [], has_more: false, next_cursor: "cursor-1")
    )
  end

  it "walks from link_token to imported transactions visible in /cash_transactions" do
    # 1 — Plaid Link asks for a link_token
    post "/api/v1/plaid/link_token", headers: auth_headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["link_token"]).to eq("link-token-xyz")

    # 2 — User finishes Plaid Link in the browser and posts back the public_token
    expect {
      post "/api/v1/plaid/items",
           params: { public_token: "public-token-abc" },
           headers: auth_headers, as: :json
    }.to change(PlaidItem, :count).by(1)
      .and change(PlaidAccount, :count).by(1)
      .and change(Account, :count).by(1)   # link_to_new_account! creates this
      .and change(Broker, :count).by(1)    # "Chase" broker auto-created

    expect(response).to have_http_status(:created)
    item_id = response.parsed_body["id"]
    expect(response.parsed_body["institution_name"]).to eq("Chase")

    # 3 — Frontend lists items and accounts
    get "/api/v1/plaid/items", headers: auth_headers
    expect(response.parsed_body.first["plaid_accounts"].length).to eq(1)

    get "/api/v1/plaid/accounts", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first["name"]).to eq("Checking")

    # 4 — User triggers a sync
    perform_enqueued_jobs do
      post "/api/v1/plaid/items/#{item_id}/sync", headers: auth_headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")
    end

    # 5 — Cash transaction now exists under the linked Account, scoped to household
    expect(CashTransaction.count).to eq(1)
    txn = CashTransaction.first
    expect(txn.description).to eq("Coffee shop")
    expect(txn.amount.to_f).to  eq(-5.25)  # plaid sign flipped on store
    expect(txn.account).to      eq(PlaidAccount.first.account)

    # 6 — /cash_transactions reflects it
    get "/api/v1/cash_transactions", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |t| t["description"] }).to include("Coffee shop")
  end
end
