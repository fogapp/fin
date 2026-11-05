require "rails_helper"

RSpec.describe RecalculatePositionService do
  let(:account)  { create(:account) }
  let(:security) { create(:security) }
  let(:purchase_type) { create(:transaction_type, :purchase) }
  let(:sale_type)     { create(:transaction_type, :sale) }
  let(:other_type)    { create(:transaction_type, :dividend) }

  def call_with(txn) = described_class.new(transaction: txn).call

  describe "#call" do
    it "returns nil for transactions outside Purchase/Sale categories" do
      txn = create(:investment_transaction, security: security, account: account,
                   transaction_type: other_type)
      expect(call_with(txn)).to be_nil
    end

    it "returns nil when the transaction has no security" do
      txn = create(:investment_transaction, security: security, account: account,
                   transaction_type: purchase_type)
      txn.update_columns(security_id: nil)
      txn.reload
      expect(call_with(txn)).to be_nil
    end

    context "with no prior snapshot" do
      it "creates a snapshot from a single purchase" do
        create(:market_price, security: security, close: 150.0)
        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 10, cost_usd: 1000)

        snap = call_with(txn)
        expect(snap).to be_persisted
        expect(snap.quantity).to     eq(10.0)
        expect(snap.cost_basis).to   eq(1000.0)
        expect(snap.price).to        eq(150.0)
        expect(snap.market_value).to eq(1500.0)
        expect(snap.unrealized_gain_loss).to eq(500.0)
        expect(snap.unrealized_gain_loss_pct).to eq(50.0)
        expect(snap.source_row_hash).to start_with("computed:")
      end

      it "returns nil and creates nothing for a net-negative position (opening sale)" do
        create(:market_price, security: security, close: 10.0)
        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: sale_type, quantity: -2, cost_usd: 50)

        expect(call_with(txn)).to be_nil
        expect(PositionSnapshot.where("source_row_hash LIKE 'computed:%'")).to be_empty
      end
    end

    context "ledger rebuild semantics" do
      it "is idempotent — reprocessing the same transaction never double-applies" do
        create(:market_price, security: security, close: 100.0)
        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 5, cost_usd: 500)

        first = call_with(txn)
        again = call_with(txn)

        expect(again.id).to eq(first.id)
        expect(again.quantity).to eq(5.0)
        expect(again.cost_basis).to eq(500.0)
      end

      it "nets purchases and sales across the whole ledger" do
        create(:market_price, security: security, close: 100.0)
        create(:investment_transaction, security: security, account: account,
               transaction_type: purchase_type, quantity: 10, cost_usd: 1000)
        sale = create(:investment_transaction, security: security, account: account,
                      transaction_type: sale_type, quantity: -4, cost_usd: 400)

        snap = call_with(sale)
        expect(snap.quantity).to eq(6.0)
        expect(snap.cost_basis).to eq(600.0)
      end

      it "destroys the computed row when the position closes to zero" do
        create(:market_price, security: security, close: 100.0)
        buy = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 5, cost_usd: 500)
        call_with(buy)
        expect(PositionSnapshot.where("source_row_hash LIKE 'computed:%'").count).to eq(1)

        sell = create(:investment_transaction, security: security, account: account,
                      transaction_type: sale_type, quantity: -5, cost_usd: 500)
        expect(call_with(sell)).to be_nil
        expect(PositionSnapshot.where("source_row_hash LIKE 'computed:%'")).to be_empty
      end

      it "replaces legacy date-suffixed computed rows instead of doubling them" do
        create(:market_price, security: security, close: 100.0)
        legacy = create(:position_snapshot, security: security, account: account,
                        as_of_date: 3.days.ago.to_date, quantity: 5,
                        source_row_hash: "computed:#{security.id}:#{account.id}:#{3.days.ago.to_date}")

        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 5, cost_usd: 500)
        snap = call_with(txn)

        expect(snap.id).to eq(legacy.id)
        expect(PositionSnapshot.where("source_row_hash LIKE 'computed:%'").count).to eq(1)
      end

      it "never touches imported or plaid snapshots and yields to a same-day observation" do
        plaid = create(:position_snapshot, security: security, account: account,
                       as_of_date: Date.current, quantity: 99,
                       source_row_hash: "plaid_holding:x:#{security.id}")

        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 5, cost_usd: 500)
        result = call_with(txn)

        # unique (account, security, date) is taken by the observation
        expect(result).to be_nil
        expect(plaid.reload.quantity).to eq(99.0)
      end

      it "falls back to the last observed snapshot price when no MarketPrice exists" do
        create(:position_snapshot, security: security, account: account,
               as_of_date: 1.week.ago.to_date, quantity: 5, price: 100.0,
               source_row_hash: "imported-row-1")

        txn = create(:investment_transaction, security: security, account: account,
                     transaction_type: purchase_type, quantity: 1, cost_usd: 100)

        snap = call_with(txn)
        expect(snap.price).to eq(100.0)
      end
    end
  end
end
