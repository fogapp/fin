require "rails_helper"

RSpec.describe PlaidSyncer do
  let(:plaid_item)    { create(:plaid_item) }
  # Credit card subtype avoids the balance: presence validation on bank-source transactions;
  # Plaid syncs don't carry per-transaction balance data.
  let(:plaid_account) do
    create(:plaid_account, plaid_item: plaid_item, account: create(:account),
           account_subtype: "credit card")
  end
  let(:client) { instance_double(PlaidClient) }

  before do
    allow(PlaidClient).to receive(:new).and_return(client)
    # sync_balances / sync_holdings / sync_investment_transactions all run at
    # the end of every #call — stub no-ops by default
    allow(client).to receive(:get_accounts).and_return(double(accounts: []))
    allow(client).to receive(:get_investment_holdings).and_return(double(holdings: [], securities: []))
    allow(client).to receive(:get_investment_transactions).and_return(
      double(investment_transactions: [], securities: [], total_investment_transactions: 0)
    )
  end

  # Builds a minimal fake Plaid transaction double
  def plaid_txn(overrides = {})
    double(
      transaction_id: overrides.fetch(:transaction_id, "txn-#{SecureRandom.hex(4)}"),
      account_id:     overrides.fetch(:account_id, plaid_account.plaid_account_id),
      name:           overrides.fetch(:name, "NETFLIX"),
      amount:         overrides.fetch(:amount, 15.99),
      date:           overrides.fetch(:date, Date.current),
      authorized_date: overrides.fetch(:authorized_date, nil),
      pending_transaction_id: overrides.fetch(:pending_transaction_id, nil),
      personal_finance_category: overrides.fetch(:pfc, nil)
    )
  end

  def sync_response(added: [], modified: [], removed: [], next_cursor: "cur-1", has_more: false)
    double(added: added, modified: modified, removed: removed,
           next_cursor: next_cursor, has_more: has_more)
  end

  def syncer(only_account: nil)
    PlaidSyncer.new(plaid_item, only_account: only_account)
  end

  describe "#call — adding transactions" do
    it "creates a CashTransaction for each added Plaid transaction" do
      txn = plaid_txn
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      expect { syncer.call }.to change(CashTransaction, :count).by(1)
      ct = CashTransaction.last
      expect(ct.description).to eq("NETFLIX")
      expect(ct.amount).to eq(-15.99)
      expect(ct.source_row_hash).to eq(txn.transaction_id)
    end

    it "uses authorized_date when available" do
      authorized = Date.current - 1.day
      txn = plaid_txn(authorized_date: authorized, date: Date.current)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      syncer.call
      expect(CashTransaction.last.transaction_date).to eq(authorized)
    end

    it "uses post date when authorized_date is nil" do
      post_date = Date.current
      txn = plaid_txn(authorized_date: nil, date: post_date)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      syncer.call
      expect(CashTransaction.last.transaction_date).to eq(post_date)
    end

    it "skips duplicate transactions by source_row_hash" do
      txn = plaid_txn(transaction_id: "dup-hash")
      create(:cash_transaction, :credit_card, :sale, source_row_hash: "dup-hash")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      expect { syncer.call }.not_to change(CashTransaction, :count)
    end

    it "inverts Plaid's amount sign convention" do
      txn = plaid_txn(amount: 50.0)   # positive in Plaid = money leaving account
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      syncer.call
      expect(CashTransaction.last.amount).to eq(-50.0)
    end

    it "creates a bank transaction for non-credit account types" do
      bank_account = create(:plaid_account,
                             plaid_item: plaid_item,
                             account: create(:account),
                             account_subtype: "checking")
      txn = plaid_txn(account_id: bank_account.plaid_account_id, amount: 500.0)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      expect { syncer.call }.to change(CashTransaction, :count).by(1)
      expect(CashTransaction.last.source).to eq("bank")
    end

    it "applies rule matching for merchant assignment" do
      merchant = create(:merchant, name: "Netflix")
      create(:merchant_rule,
             merchant: merchant,
             pattern: "NETFLIX",
             priority: 1)
      Merchants::RuleMatcher.reset_cache

      txn = plaid_txn(name: "NETFLIX MONTHLY")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      syncer.call
      expect(CashTransaction.last.merchant).to eq(merchant)
    end

    it "triggers Recurring::DetectJob after adding transactions" do
      txn = plaid_txn
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      expect { syncer.call }.to have_enqueued_job(Recurring::DetectJob)
    end
  end

  describe "#call — modifying transactions" do
    it "updates description and amount on an existing transaction" do
      existing = create(:cash_transaction, :credit_card, :sale, source_row_hash: "txn-mod-1")
      txn = plaid_txn(transaction_id: "txn-mod-1", name: "UPDATED NAME", amount: 29.99)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(modified: [ txn ])
      )

      syncer.call
      expect(existing.reload.description).to eq("UPDATED NAME")
      expect(existing.reload.amount).to eq(-29.99)
    end

    it "skips modification when source_row_hash is not found" do
      txn = plaid_txn(transaction_id: "unknown-hash")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(modified: [ txn ])
      )

      expect { syncer.call }.not_to change(CashTransaction, :count)
    end
  end

  describe "#call — removing transactions" do
    it "destroys the matching transaction" do
      existing = create(:cash_transaction, :credit_card, :sale, source_row_hash: "txn-rm-1")
      txn = plaid_txn(transaction_id: "txn-rm-1")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(removed: [ txn ])
      )

      expect { syncer.call }.to change(CashTransaction, :count).by(-1)
      expect(CashTransaction.exists?(existing.id)).to be false
    end
  end

  describe "#call — pending→posted settlement" do
    it "adopts the pending row instead of destroying and recreating it" do
      merchant = create(:merchant, name: "Corner Store")
      category = create(:category)
      pending = create(:cash_transaction, :credit_card, :sale,
                       source_row_hash: "pending-1", merchant: merchant,
                       category: category, memo: "split with roommate")
      posted = plaid_txn(transaction_id: "posted-1", pending_transaction_id: "pending-1",
                         name: "CORNER STORE #42", amount: 23.45)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ posted ], removed: [ plaid_txn(transaction_id: "pending-1") ])
      )

      expect { syncer.call }.not_to change(CashTransaction, :count)
      pending.reload
      expect(pending.source_row_hash).to eq("posted-1")
      expect(pending.description).to eq("CORNER STORE #42")
      expect(pending.amount).to eq(-23.45)
      expect(pending.merchant).to eq(merchant)
      expect(pending.category).to eq(category)
      expect(pending.memo).to eq("split with roommate")
    end

    it "preserves a confirmed transfer through settlement" do
      pending = create(:cash_transaction, :credit_card, :sale, source_row_hash: "pending-2")
      other_leg = create(:cash_transaction, :credit_card, :sale)
      transfer = create(:transfer, :confirmed,
                        from_transaction_id: pending.id, from_transaction_type: "CashTransaction",
                        to_transaction_id: other_leg.id, to_transaction_type: "CashTransaction")
      pending.update!(transfer_id: transfer.id)
      other_leg.update!(transfer_id: transfer.id)
      posted = plaid_txn(transaction_id: "posted-2", pending_transaction_id: "pending-2")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ posted ], removed: [ plaid_txn(transaction_id: "pending-2") ])
      )

      expect { syncer.call }.not_to change(Transfer, :count)
      expect(pending.reload.transfer_id).to eq(transfer.id)
      expect(pending.source_row_hash).to eq("posted-2")
    end

    it "re-probes payment matching and replays created-triggered workflows once the posted values land" do
      create(:workflow, trigger_type: "cash_transaction.created")
      pending = create(:cash_transaction, :credit_card, :sale, source_row_hash: "pending-4",
                       description: "APPLE CARD", amount: -1292.82)
      posted = plaid_txn(transaction_id: "posted-4", pending_transaction_id: "pending-4",
                         name: "APPLECARD GSBANK PAYMENT 100001 WEB ID: 9999999999", amount: 1292.82)
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ posted ]))

      expect { syncer.call }
        .to have_enqueued_job(Transfers::PaymentMatchJob).with(pending.id)
        .and have_enqueued_job(Workflows::DispatchJob)
          .with("cash_transaction.created", pending.household_id, "CashTransaction", pending.id,
                { "replay" => "posted", "changes" => [ "description" ] })
    end

    it "does not replay when settlement changed nothing that matching keys on" do
      create(:workflow, trigger_type: "cash_transaction.created")
      pending = create(:cash_transaction, :credit_card, :sale, source_row_hash: "pending-5",
                       description: "NETFLIX", amount: -15.99, transaction_date: Date.current)
      posted = plaid_txn(transaction_id: "posted-5", pending_transaction_id: "pending-5",
                         name: "NETFLIX", amount: 15.99)
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ posted ]))

      expect { syncer.call }.not_to have_enqueued_job(Transfers::PaymentMatchJob)
    end

    it "fills merchant from rules on the posted description when the row has none" do
      merchant = create(:merchant, name: "Netflix")
      create(:merchant_rule, merchant: merchant, pattern: "NETFLIX", priority: 1)
      Merchants::RuleMatcher.reset_cache

      create(:cash_transaction, :credit_card, :sale,
             source_row_hash: "pending-3", description: "PENDING CARD 1234", merchant: nil)
      posted = plaid_txn(transaction_id: "posted-3", pending_transaction_id: "pending-3",
                         name: "NETFLIX MONTHLY")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ posted ])
      )

      syncer.call
      expect(CashTransaction.find_by(source_row_hash: "posted-3").merchant).to eq(merchant)
    end
  end

  describe "#call — typing card credits" do
    it "types a card credit with a payment signature as Payment whatever Plaid's category says" do
      txn = plaid_txn(name: "AUTOMATIC PAYMENT - THANK", amount: -845.23,
                      pfc: double(primary: "INCOME", detailed: "INCOME_SALARY"))
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ txn ]))

      syncer.call

      expect(CashTransaction.last.transaction_type).to eq("Payment")
    end

    it "still types an ordinary card credit as a Return" do
      txn = plaid_txn(name: "Amazon.com", amount: -36.45,
                      pfc: double(primary: "GENERAL_MERCHANDISE", detailed: "GENERAL_MERCHANDISE_ONLINE_MARKETPLACES"))
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ txn ]))

      syncer.call

      expect(CashTransaction.last.transaction_type).to eq("Return")
    end
  end

  describe "#call — cursor handling" do
    it "advances the item cursor on a full sync that returned data" do
      # The first sync needs to actually return a transaction; the initial-sync
      # guard (commit 3d3a53d) keeps cursor nil when result.added is zero so
      # Plaid's async backfill isn't accidentally skipped.
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ plaid_txn ], next_cursor: "cursor-new")
      )

      syncer.call
      expect(plaid_item.reload.cursor).to eq("cursor-new")
    end

    it "leaves the cursor nil when the initial sync returns no transactions" do
      # Regression for commit 3d3a53d — Plaid processes historical transactions
      # asynchronously, so the first sync often returns 0. Saving the cursor
      # then would permanently skip the backfill.
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(next_cursor: "cursor-new")
      )

      syncer.call
      expect(plaid_item.reload.cursor).to be_nil
      expect(plaid_item.last_synced_at).not_to be_nil
    end

    it "does not advance the item cursor for a single-account sync" do
      plaid_item.update!(cursor: "cursor-original")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(next_cursor: "cursor-new")
      )

      syncer(only_account: plaid_account).call
      expect(plaid_item.reload.cursor).to eq("cursor-original")
    end

    it "paginates when has_more is true" do
      # Distinct content per page — identical name/amount/date would trip the
      # content-based reconnect dedup in process_added and merge, not create.
      page1 = sync_response(added: [ plaid_txn(name: "PAGE ONE") ], next_cursor: "cur-2", has_more: true)
      page2 = sync_response(added: [ plaid_txn(name: "PAGE TWO") ], next_cursor: "cur-3", has_more: false)
      allow(client).to receive(:sync_transactions).and_return(page1, page2)

      expect { syncer.call }.to change(CashTransaction, :count).by(2)
    end

    it "holds the cursor at the last clean page and stops paging when a transaction fails" do
      plaid_item.update!(cursor: "cursor-0")
      page1 = sync_response(added: [ plaid_txn(name: "GOOD ONE") ], next_cursor: "cur-2", has_more: true)
      page2 = sync_response(added: [ plaid_txn(name: "BAD ONE") ],  next_cursor: "cur-3", has_more: true)
      allow(client).to receive(:sync_transactions).and_return(page1, page2)
      allow(Merchants::RuleMatcher).to receive(:match_result).and_call_original
      allow(Merchants::RuleMatcher).to receive(:match_result).with("BAD ONE").and_raise(StandardError, "boom")

      result = syncer.call

      expect(result.errors.size).to eq(1)
      # Page 1 applied cleanly so its cursor persisted; the failing page's
      # cursor must not — Plaid never re-delivers behind a saved cursor.
      expect(plaid_item.reload.cursor).to eq("cur-2")
      # Paging stopped at the failing page instead of continuing past it.
      expect(client).to have_received(:sync_transactions).twice
      expect(ActivityEntry.find_by!(event: "sync.completed").severity).to eq(Severity::Error)
    end
  end

  describe "#call — content dedup gating" do
    let!(:existing) do
      create(:cash_transaction, :credit_card, :sale,
             account: plaid_account.account, transaction_date: Date.current,
             amount: -15.99, description: "NETFLIX", source_row_hash: "old-hash")
    end

    it "adopts the new Plaid ID into the content-matching row on a first sync (reconnect)" do
      expect(plaid_item.cursor).to be_nil
      txn = plaid_txn(transaction_id: "new-plaid-id")
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ txn ]))

      expect { syncer.call }.not_to change(CashTransaction, :count)
      expect(existing.reload.source_row_hash).to eq("new-plaid-id")
      expect(Issue.find_by(title: "Duplicate Plaid transaction merged")).to be_present
    end

    it "creates a distinct transaction on an incremental sync even when content matches" do
      plaid_item.update!(cursor: "cursor-existing")
      txn = plaid_txn(transaction_id: "new-plaid-id")
      allow(client).to receive(:sync_transactions).and_return(sync_response(added: [ txn ]))

      expect { syncer.call }.to change(CashTransaction, :count).by(1)
      expect(existing.reload.source_row_hash).to eq("old-hash")
      expect(CashTransaction.find_by(source_row_hash: "new-plaid-id")).to be_present
    end
  end

  describe "#call — sub-sync failure visibility" do
    it "tallies balance-sync failures as a warning without holding the cursor back" do
      plaid_item.update!(cursor: "cursor-0")
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ plaid_txn ], next_cursor: "cursor-new")
      )
      allow(client).to receive(:get_accounts).and_raise(StandardError, "balance fetch failed")

      result = syncer.call

      expect(result.errors).to be_empty
      expect(result.sub_errors).to include(hash_including(scope: "balances"))
      expect(plaid_item.reload.cursor).to eq("cursor-new")
      expect(ActivityEntry.find_by!(event: "sync.completed").severity).to eq(Severity::Warning)
    end
  end

  describe "#call — account filtering" do
    it "skips transactions for other accounts when only_account is set" do
      other_account = create(:plaid_account, plaid_item: plaid_item, account: create(:account))
      txn = plaid_txn(account_id: other_account.plaid_account_id)
      allow(client).to receive(:sync_transactions).and_return(
        sync_response(added: [ txn ])
      )

      expect { syncer(only_account: plaid_account).call }.not_to change(CashTransaction, :count)
    end
  end

  describe "#call — error handling" do
    it "marks the item as error and re-raises on Plaid::ApiError" do
      error = Plaid::ApiError.new
      allow(error).to receive(:response_body).and_return('{"error_message":"INVALID_ACCESS_TOKEN"}')
      allow(client).to receive(:sync_transactions).and_raise(error)

      expect { syncer.call }.to raise_error(Plaid::ApiError)
      expect(plaid_item.reload.status).to eq("error")
      expect(plaid_item.reload.error_message).to include("INVALID_ACCESS_TOKEN")
    end

    it "marks the item as error and re-raises on generic errors" do
      allow(client).to receive(:sync_transactions).and_raise(StandardError, "network failure")

      expect { syncer.call }.to raise_error(StandardError, "network failure")
      expect(plaid_item.reload.status).to eq("error")
    end
  end

  describe "#sync_balances" do
    def plaid_account_response(plaid_account_id:, current:, available:, limit: nil)
      balances = double(current: current, available: available, limit: limit,
                        iso_currency_code: "USD", unofficial_currency_code: nil)
      double(account_id: plaid_account_id, balances: balances)
    end

    def accounts_response(accounts)
      double(accounts: accounts)
    end

    it "updates balance fields on the linked PlaidAccount after a sync call" do
      acct_response = plaid_account_response(
        plaid_account_id: plaid_account.plaid_account_id,
        current:          1234.56,
        available:        1000.00,
        limit:            nil
      )

      allow(client).to receive(:sync_transactions).and_return(sync_response)
      allow(client).to receive(:get_accounts).and_return(accounts_response([ acct_response ]))

      syncer.call

      plaid_account.reload
      expect(plaid_account.balance_current).to   eq(1234.56)
      expect(plaid_account.balance_available).to eq(1000.00)
      expect(plaid_account.balance_limit).to     be_nil
      expect(plaid_account.balance_currency).to  eq("USD")
      expect(plaid_account.balance_updated_at).to be_present
    end

    it "does not raise if get_accounts fails" do
      allow(client).to receive(:sync_transactions).and_return(sync_response)
      allow(client).to receive(:get_accounts).and_raise(StandardError, "balance fetch failed")

      expect { syncer.call }.not_to raise_error
    end
  end

  describe "#sync_holdings" do
    let(:wallet_account) do
      create(:plaid_account, plaid_item: plaid_item, account: create(:account),
             account_type: "investment", account_subtype: "non-custodial wallet")
    end

    def plaid_security(id:, ticker:, name:, close_price: nil, type: "cryptocurrency")
      double(security_id: id, ticker_symbol: ticker, cusip: nil, name: name,
             type: type, close_price: close_price)
    end

    def plaid_holding(plaid_acct, security_id:, quantity:, institution_price: 0.0,
                      institution_value: 0.0, cost_basis: nil)
      double(account_id: plaid_acct.plaid_account_id, security_id: security_id,
             quantity: quantity, institution_price: institution_price,
             institution_value: institution_value, cost_basis: cost_basis)
    end

    def holdings_response(holdings:, securities:)
      double(holdings: holdings, securities: securities)
    end

    before do
      allow(client).to receive(:sync_transactions).and_return(sync_response)
    end

    it "values wallet holdings from the security close_price when institution pricing is zero" do
      # Crypto wallets report institution_price/value = 0 and no cost basis;
      # the only USD price in the response is close_price on the security.
      eth = plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ plaid_holding(wallet_account, security_id: "ps-eth", quantity: 4.1667) ],
                          securities: [ eth ])
      )

      syncer.call

      snap = PositionSnapshot.find_by!(account_id: wallet_account.account_id)
      expect(snap.price.to_f).to eq(1800.0)
      expect(snap.market_value.to_f).to eq(7500.06)
      expect(snap.cost_basis).to be_nil
      expect(snap.unrealized_gain_loss).to be_nil
      expect(snap.unrealized_gain_loss_pct).to be_nil
    end

    it "derives the wallet account balance from total holdings value" do
      securities = [
        plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0),
        plaid_security(id: "ps-usdc", ticker: "USDC", name: "USD Coin", close_price: 1.0)
      ]
      holdings = [
        plaid_holding(wallet_account, security_id: "ps-eth", quantity: 4.0),
        plaid_holding(wallet_account, security_id: "ps-usdc", quantity: 56.0)
      ]
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: holdings, securities: securities)
      )

      syncer.call

      account = wallet_account.account.reload
      expect(account.balance.to_f).to eq(7256.0)
      expect(account.balance_usd.to_f).to eq(7256.0)
      snapshot = AccountBalanceSnapshot.find_by!(account_id: account.id)
      expect(snapshot.balance.to_f).to eq(7256.0)
      expect(snapshot.source).to eq(AccountBalanceSnapshot::Source::PlaidSync)
    end

    it "does not overwrite the wallet balance with Plaid's $0 account-level balance" do
      balances = double(current: 0.0, available: nil, limit: nil,
                        iso_currency_code: "USD", unofficial_currency_code: nil)
      allow(client).to receive(:get_accounts).and_return(
        double(accounts: [ double(account_id: wallet_account.plaid_account_id, balances: balances) ])
      )
      eth = plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ plaid_holding(wallet_account, security_id: "ps-eth", quantity: 2.0) ],
                          securities: [ eth ])
      )

      syncer.call

      account = wallet_account.account.reload
      expect(account.balance.to_f).to eq(3600.0)
      # The Plaid-reported $0 must not leave a snapshot behind either.
      expect(AccountBalanceSnapshot.where(account_id: account.id).pluck(:balance)).to eq([ 3600.0 ])
      # The PlaidAccount mirror still reflects what Plaid reported.
      expect(wallet_account.reload.balance_current).to eq(0.0)
    end

    it "keeps institution pricing for brokerage holdings" do
      brokerage = create(:plaid_account, plaid_item: plaid_item, account: create(:account),
                         account_type: "investment", account_subtype: "brokerage")
      aapl = plaid_security(id: "ps-aapl", ticker: "AAPL", name: "Apple Inc", type: "equity", close_price: 199.0)
      holding = plaid_holding(brokerage, security_id: "ps-aapl", quantity: 10.0,
                              institution_price: 190.0, institution_value: 1900.0, cost_basis: 1500.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ holding ], securities: [ aapl ])
      )

      syncer.call

      snap = PositionSnapshot.find_by!(account_id: brokerage.account_id)
      expect(snap.price.to_f).to eq(190.0)
      expect(snap.market_value.to_f).to eq(1900.0)
      expect(snap.cost_basis.to_f).to eq(1500.0)
      expect(snap.unrealized_gain_loss.to_f).to eq(400.0)
      # Non-wallet accounts never get a holdings-derived balance.
      expect(brokerage.account.reload.balance).to be_nil
    end

    it "keeps a custodian price history for holdings no market provider covers" do
      brokerage = create(:plaid_account, plaid_item: plaid_item, account: create(:account),
                         account_type: "investment", account_subtype: "brokerage")
      muni = double(security_id: "ps-muni", ticker_symbol: nil, cusip: "797669WT1", name: "San Fran Ca 4.0%07/01/27",
                    type: "fixed income", close_price: nil)
      aapl = plaid_security(id: "ps-aapl", ticker: "AAPL", name: "Apple Inc", type: "equity", close_price: 199.0)
      bond_holding = double(account_id: brokerage.plaid_account_id, security_id: "ps-muni", quantity: 25_000.0,
                            institution_price: 100.0404, institution_value: 25_010.09, cost_basis: nil,
                            institution_price_as_of: Date.current - 1)
      stock_holding = plaid_holding(brokerage, security_id: "ps-aapl", quantity: 10.0,
                                    institution_price: 190.0, institution_value: 1900.0)
      allow(AlphaVantage).to receive(:configured?).and_return(true)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ bond_holding, stock_holding ], securities: [ muni, aapl ])
      )

      syncer.call

      bond = Security.find_by!(cusip: "797669WT1")
      expect(Candle.where(security: bond).pluck(:date, :close, :source))
        .to eq([ [ Date.current - 1, BigDecimal("100.0404"), "custodian" ] ])
      expect(bond.quoted_per_hundred?).to be(true)
      # A listed equity keeps waiting for its market provider.
      expect(Candle.where(security: Security.find_by!(ticker: "AAPL"))).to be_empty
    end

    it "zero-stamps snapshots for holdings that disappeared from the response" do
      sold = create(:security, ticker: "SOLD")
      stale = create(:position_snapshot,
                     account: wallet_account.account, security: sold,
                     source_row_hash: "plaid_holding:#{wallet_account.id}:#{sold.id}",
                     quantity: 5, market_value: 500.0, as_of_date: Date.current - 1)
      eth = plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ plaid_holding(wallet_account, security_id: "ps-eth", quantity: 2.0) ],
                          securities: [ eth ])
      )

      syncer.call

      stale.reload
      expect(stale.quantity).to eq(0)
      expect(stale.market_value).to eq(0)
      expect(stale.as_of_date).to eq(Date.current)
      # The holding still present keeps its real quantity.
      kept = PositionSnapshot.find_by!(source_row_hash: "plaid_holding:#{wallet_account.id}:#{Security.find_by!(ticker: 'ETH').id}")
      expect(kept.quantity).to eq(2)
    end

    it "does not zero-stamp when a holding in the response failed to process" do
      sold = create(:security, ticker: "SOLD")
      stale = create(:position_snapshot,
                     account: wallet_account.account, security: sold,
                     source_row_hash: "plaid_holding:#{wallet_account.id}:#{sold.id}",
                     quantity: 5, as_of_date: Date.current - 1)
      eth = plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(holdings: [ plaid_holding(wallet_account, security_id: "ps-eth", quantity: 2.0) ],
                          securities: [ eth ])
      )
      allow(PositionSnapshot).to receive(:find_or_initialize_by).and_raise(StandardError, "db hiccup")

      result = syncer.call

      # A failed holding might still be held — zeroing it could book a
      # phantom ADJ-OUT via reconciliation.
      expect(result.sub_errors).to include(hash_including(scope: "holding"))
      expect(stale.reload.quantity).to eq(5)
    end

    it "still zero-stamps the accounts a failing holding does not belong to" do
      brokerage = create(:plaid_account, plaid_item: plaid_item, account: create(:account),
                         account_type: "investment", account_subtype: "brokerage")
      sold = create(:security, ticker: "SOLD")
      stale = create(:position_snapshot,
                     account: brokerage.account, security: sold,
                     source_row_hash: "plaid_holding:#{brokerage.id}:#{sold.id}",
                     quantity: 5, market_value: 500.0, as_of_date: Date.current - 1)
      eth  = plaid_security(id: "ps-eth", ticker: "ETH", name: "Ethereum", close_price: 1800.0)
      aapl = plaid_security(id: "ps-aapl", ticker: "AAPL", name: "Apple Inc", type: "equity", close_price: 199.0)
      allow(client).to receive(:get_investment_holdings).and_return(
        holdings_response(
          holdings:   [ plaid_holding(wallet_account, security_id: "ps-eth", quantity: 2.0),
                        plaid_holding(brokerage, security_id: "ps-aapl", quantity: 1.0,
                                      institution_price: 199.0, institution_value: 199.0) ],
          securities: [ eth, aapl ]
        )
      )
      # Only the wallet account's holding fails.
      allow(PositionSnapshot).to receive(:find_or_initialize_by).and_wrap_original do |orig, args|
        raise StandardError, "db hiccup" if args[:source_row_hash].to_s.start_with?("plaid_holding:#{wallet_account.id}:")

        orig.call(args)
      end

      result = syncer.call

      # One account's failure used to freeze every other account's stale rows
      # for as long as it kept failing.
      expect(result.sub_errors).to include(hash_including(scope: "holding"))
      expect(stale.reload.quantity).to eq(0)
      expect(stale.as_of_date).to eq(Date.current)
    end
  end

  describe "#sync_investment_transactions — crypto wallet noise" do
    def plaid_inv_txn(overrides = {})
      defaults = {
        investment_transaction_id: "inv-#{SecureRandom.hex(4)}",
        account_id: plaid_account.plaid_account_id,
        security_id: nil,
        date: Date.current,
        quantity: 0.0,
        price: 0.0,
        amount: 0.0,
        fees: 0.0,
        type: "fee",
        subtype: "",
        name: "fee - ETH - 10"
      }
      double(defaults.merge(overrides))
    end

    before do
      allow(client).to receive(:sync_transactions).and_return(sync_response)
    end

    def stub_investment_transactions(txns)
      allow(client).to receive(:get_investment_transactions).and_return(
        double(investment_transactions: txns, securities: [], total_investment_transactions: txns.size)
      )
    end

    it "skips zero-amount fee rows (on-chain transfer noise)" do
      stub_investment_transactions([ plaid_inv_txn(quantity: 888_888.0) ])

      expect { syncer.call }.not_to change(InvestmentTransaction, :count)
    end

    it "still imports fee rows that carry a real amount" do
      stub_investment_transactions([ plaid_inv_txn(amount: 25.0, name: "ADVISORY FEE") ])

      expect { syncer.call }.to change(InvestmentTransaction, :count).by(1)
      txn = InvestmentTransaction.last
      expect(txn.transaction_type.code).to eq("FEE")
      expect(txn.amount_usd.to_f).to eq(25.0)
    end
  end
end
