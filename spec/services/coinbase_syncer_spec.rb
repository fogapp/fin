require "rails_helper"

RSpec.describe CoinbaseSyncer do
  let!(:buy_tt)  { create(:transaction_type, code: "BUY",  code_description: "Bought", category: "Purchase") }
  let!(:sell_tt) { create(:transaction_type, code: "SELL", code_description: "Sold",   category: "Sale") }

  # Sorbet's runtime T.let in CoinbaseSyncer#initialize rejects instance_double,
  # so we hand the syncer a real CoinbaseClient instance whose methods we stub.
  let(:client) do
    seed = SecureRandom.bytes(32)
    CoinbaseConfiguration.create!(
      api_key_id:     "test-key-id",
      api_key_secret: Base64.strict_encode64(seed + SecureRandom.bytes(32))
    )
    CoinbaseClient.new
  end

  before do
    allow(CoinbaseClient).to receive(:new).and_return(client)
    allow(client).to receive(:account_transactions).and_return("data" => [], "pagination" => {})
  end

  def stub_accounts(list)
    allow(client).to receive(:accounts).and_return(list)
  end

  def stub_transactions(account_id, pages)
    responses = pages.map { |p| { "data" => p[:data], "pagination" => { "next_uri" => p[:next_uri] } } }
    allow(client).to receive(:account_transactions)
      .with(account_id, hash_including(limit: 100)) { responses.shift || { "data" => [], "pagination" => {} } }
  end

  describe "#call" do
    it "creates an Account on first sync and records a balance snapshot" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0.5", "currency" => "BTC" },
          "native_balance" => { "amount" => "30000.00", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [ { data: [], next_uri: nil } ])

      expect { described_class.new.call }
        .to change(Account, :count).by(1)
        .and change(AccountBalanceSnapshot, :count).by(1)
        .and change { Security.where(security_type: "Crypto", ticker: "BTC").count }.by(1)

      account = Account.find_by(account_number: "acc-1")
      expect(account.balance).to            eq(0.5)
      expect(account.balance_currency).to   eq("BTC")
      expect(account.balance_usd).to        eq(30000.0)
      expect(Broker.find_by(name: "Coinbase")).to be_present
      # Balances register the instrument but must never join the watchlist:
      # auto-watching re-added coins the user had removed on every sync.
      expect(Security.find_by(ticker: "BTC", security_type: "Crypto").watched_by?(account.household)).to be false
      expect(SecurityWatch.unscoped.count).to eq(0)
    end

    it "imports a buy transaction with computed quantities and fees" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0.5", "currency" => "BTC" },
          "native_balance" => { "amount" => "30000.00", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [
        { data: [
            { "id" => "tx-1", "type" => "buy", "status" => "completed",
              "created_at" => "2026-01-01T00:00:00Z",
              "amount" => { "amount" => "0.5", "currency" => "BTC" },
              "native_amount" => { "amount" => "30000.00", "currency" => "USD" },
              "buy" => { "fee" => { "amount" => "10.00" } } }
          ], next_uri: nil }
      ])

      result = described_class.new.call
      expect(result.added).to eq(1)

      txn = InvestmentTransaction.find_by(source_row_hash: "tx-1")
      expect(txn).to be_present
      expect(txn.transaction_type).to eq(buy_tt)
      expect(txn.quantity).to         eq(0.5)
      expect(txn.amount_usd).to       eq(30000.0)
      expect(txn.price_usd).to        eq(60000.0)
      expect(txn.commissions_usd).to  eq(10.0)
    end

    it "imports a sell transaction with the SELL transaction type" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0", "currency" => "BTC" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [
        { data: [
            { "id" => "tx-sell-1", "type" => "sell", "status" => "completed",
              "created_at" => "2026-02-01T00:00:00Z",
              "amount" => { "amount" => "1.0", "currency" => "BTC" },
              "native_amount" => { "amount" => "60000.00", "currency" => "USD" },
              "sell" => { "fee" => { "amount" => "5.00" } } }
          ], next_uri: nil }
      ])

      described_class.new.call
      txn = InvestmentTransaction.find_by(source_row_hash: "tx-sell-1")
      expect(txn.transaction_type).to eq(sell_tt)
      expect(txn.commissions_usd).to  eq(5.0)
    end

    it "imports an advanced_trade_fill with the right side type" do
      stub_accounts([
        { "id" => "acc-1", "name" => "ETH Wallet",
          "balance" => { "amount" => "0", "currency" => "ETH" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [
        { data: [
            { "id" => "tx-fill-1", "type" => "advanced_trade_fill", "status" => "completed",
              "created_at" => "2026-03-01T00:00:00Z",
              "amount" => { "amount" => "2.0", "currency" => "ETH" },
              "native_amount" => { "amount" => "6000.00", "currency" => "USD" },
              "advanced_trade_fill" => { "order_side" => "buy", "commission" => "2.50" } }
          ], next_uri: nil }
      ])

      described_class.new.call
      txn = InvestmentTransaction.find_by(source_row_hash: "tx-fill-1")
      expect(txn.transaction_type).to eq(buy_tt)
      expect(txn.commissions_usd).to  eq(2.5)
    end

    it "skips non-completed transactions" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0", "currency" => "USD" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [
        { data: [
            { "id" => "tx-pending", "type" => "buy", "status" => "pending",
              "created_at" => "2026-01-01T00:00:00Z",
              "amount" => { "amount" => "1.0", "currency" => "BTC" },
              "native_amount" => { "amount" => "100.00", "currency" => "USD" },
              "buy" => { "fee" => { "amount" => "0" } } }
          ], next_uri: nil }
      ])

      result = described_class.new.call
      expect(result.added).to eq(0)
      expect(InvestmentTransaction.where(source_row_hash: "tx-pending")).to be_empty
    end

    it "skips unsupported transaction types" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0", "currency" => "USD" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [
        { data: [
            { "id" => "tx-send", "type" => "send", "status" => "completed",
              "created_at" => "2026-01-01T00:00:00Z",
              "amount" => { "amount" => "1.0", "currency" => "BTC" },
              "native_amount" => { "amount" => "0", "currency" => "USD" } }
          ], next_uri: nil }
      ])

      result = described_class.new.call
      expect(result.added).to eq(0)
    end

    it "deduplicates re-imported transactions" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0", "currency" => "USD" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      txn_payload = {
        "id" => "tx-existing", "type" => "buy", "status" => "completed",
        "created_at" => "2026-01-01T00:00:00Z",
        "amount" => { "amount" => "1.0", "currency" => "BTC" },
        "native_amount" => { "amount" => "100.00", "currency" => "USD" },
        "buy" => { "fee" => { "amount" => "0" } }
      }
      stub_transactions("acc-1", [ { data: [ txn_payload ], next_uri: nil } ])

      described_class.new.call
      stub_transactions("acc-1", [ { data: [ txn_payload ], next_uri: nil } ])

      expect { described_class.new.call }.not_to change(InvestmentTransaction, :count)
    end

    it "follows pagination via the next_uri's starting_after parameter" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0", "currency" => "USD" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])

      page1 = {
        "data" => [
          { "id" => "tx-1", "type" => "buy", "status" => "completed",
            "created_at" => "2026-01-01T00:00:00Z",
            "amount" => { "amount" => "1.0", "currency" => "BTC" },
            "native_amount" => { "amount" => "100.00", "currency" => "USD" },
            "buy" => { "fee" => { "amount" => "0" } } }
        ],
        "pagination" => { "next_uri" => "/v2/accounts/acc-1/transactions?starting_after=cursor-1" }
      }
      page2 = {
        "data" => [
          { "id" => "tx-2", "type" => "buy", "status" => "completed",
            "created_at" => "2026-01-02T00:00:00Z",
            "amount" => { "amount" => "1.0", "currency" => "BTC" },
            "native_amount" => { "amount" => "200.00", "currency" => "USD" },
            "buy" => { "fee" => { "amount" => "0" } } }
        ],
        "pagination" => {}
      }

      allow(client).to receive(:account_transactions).with("acc-1", hash_including(starting_after: nil)).and_return(page1)
      allow(client).to receive(:account_transactions).with("acc-1", hash_including(starting_after: "cursor-1")).and_return(page2)

      result = described_class.new.call
      expect(result.added).to eq(2)
    end

    it "records balance changes in subsequent syncs" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0.5", "currency" => "BTC" },
          "native_balance" => { "amount" => "30000.00", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [ { data: [], next_uri: nil } ])
      described_class.new.call

      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0.7", "currency" => "BTC" },
          "native_balance" => { "amount" => "42000.00", "currency" => "USD" } }
      ])
      # Same-day snapshots dedupe to one row per (account, day, source) —
      # the second sync updates today's snapshot in place.
      expect { described_class.new.call }
        .not_to change(AccountBalanceSnapshot, :count)

      expect(AccountBalanceSnapshot.where(source: "coinbase_sync").sole.balance).to eq(0.7)
      expect(Account.find_by(account_number: "acc-1").balance).to eq(0.7)
    end

    it "does not snapshot when balance is unchanged" do
      stub_accounts([
        { "id" => "acc-1", "name" => "BTC Wallet",
          "balance" => { "amount" => "0.5", "currency" => "BTC" },
          "native_balance" => { "amount" => "30000.00", "currency" => "USD" } }
      ])
      stub_transactions("acc-1", [ { data: [], next_uri: nil } ])
      described_class.new.call

      expect { described_class.new.call }.not_to change(AccountBalanceSnapshot, :count)
    end

    it "collects per-account errors instead of aborting the sync" do
      allow(client).to receive(:accounts).and_return([
        { "id" => "good", "name" => "Good",
          "balance" => { "amount" => "0", "currency" => "USD" },
          "native_balance" => { "amount" => "0", "currency" => "USD" } }
      ])
      allow(client).to receive(:account_transactions).with("good", anything).and_raise("network down")

      result = described_class.new.call
      expect(result.errors).to include(hash_including(account: "Good", error: "network down"))
    end
  end
end
