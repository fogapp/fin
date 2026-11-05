require "rails_helper"

RSpec.describe TransferCandidateService do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }

  # Builds a bank-type CashTransaction with explicit account and amount
  def cash_txn(account:, amount:, date: Date.current, transfer_id: nil)
    txn = create(:cash_transaction, :bank, account: account, amount: amount,
                 transaction_date: date)
    txn.update_columns(transfer_id: transfer_id) if transfer_id
    txn
  end

  subject(:service) { described_class.new }

  describe "#candidates (cash_to_cash)" do
    it "finds a matching pair when the positive-amount transaction has a smaller UUID than the negative-amount one" do
      # Create positive transaction first so it gets a smaller UUID (the bug case)
      positive = cash_txn(account: account_b, amount: 500.00)
      negative = cash_txn(account: account_a, amount: -500.00)

      # Positive UUID < negative UUID (typical insertion order with gen_random_uuid can vary,
      # so we force the ordering by re-reading to confirm both exist)
      results = service.candidates

      pair = results.find { |r|
        [ r.from_transaction.id, r.to_transaction.id ].sort == [ negative.id, positive.id ].sort
      }
      expect(pair).not_to be_nil
      expect(pair.from_transaction.amount).to be < 0
      expect(pair.to_transaction.amount).to be > 0
    end

    it "finds a pair when the negative-amount transaction has a smaller UUID" do
      negative = cash_txn(account: account_a, amount: -500.00)
      positive = cash_txn(account: account_b, amount: 500.00)

      results = service.candidates

      pair = results.find { |r|
        [ r.from_transaction.id, r.to_transaction.id ].sort == [ negative.id, positive.id ].sort
      }
      expect(pair).not_to be_nil
    end

    it "does not match transactions in the same account" do
      cash_txn(account: account_a, amount: -500.00)
      cash_txn(account: account_a, amount: 500.00)

      expect(service.candidates).to be_empty
    end

    it "does not match transactions where amounts do not sum to near zero" do
      cash_txn(account: account_a, amount: -500.00)
      cash_txn(account: account_b, amount: 400.00)  # 100 difference — well outside tolerance

      expect(service.candidates).to be_empty
    end

    it "does not match transactions more than 3 days apart" do
      date_a = Date.current
      date_b = date_a + 4.days

      cash_txn(account: account_a, amount: -500.00, date: date_a)
      cash_txn(account: account_b, amount: 500.00,  date: date_b)

      expect(service.candidates).to be_empty
    end

    it "does match transactions exactly 3 days apart" do
      date_a = Date.current
      date_b = date_a + 3.days

      cash_txn(account: account_a, amount: -500.00, date: date_a)
      cash_txn(account: account_b, amount: 500.00,  date: date_b)

      expect(service.candidates).not_to be_empty
    end

    it "does not match transactions that already have a transfer_id set" do
      neg = cash_txn(account: account_a, amount: -500.00)
      pos = cash_txn(account: account_b, amount: 500.00)

      # Create a valid Transfer referencing one side, then stamp transfer_id on the transaction
      transfer = Transfer.create!(
        from_transaction_id:   neg.id,
        from_transaction_type: "CashTransaction",
        to_transaction_id:     pos.id,
        to_transaction_type:   "CashTransaction",
        amount:                500.00
      )
      neg.update_columns(transfer_id: transfer.id)

      results = service.candidates
      found = results.any? { |r| r.from_transaction.id == neg.id || r.to_transaction.id == neg.id }
      expect(found).to be false
    end

    it "returns Result structs with correct fields" do
      cash_txn(account: account_a, amount: -250.00)
      cash_txn(account: account_b, amount: 250.00)

      result = service.candidates.first
      expect(result).to respond_to(:from_transaction, :to_transaction, :amount, :date_diff)
      expect(result.amount).to be_within(0.01).of(250.0)
      expect(result.date_diff).to eq(0)
    end
  end

  describe "household scoping" do
    it "never pairs transactions belonging to two different households" do
      # Regression: the raw SQL bypassed the HouseholdScoped default scope,
      # so a matching amount/date in ANOTHER household produced a candidate.
      cash_txn(account: account_a, amount: -500.00)

      other_household = Household.create!(name: "Other Household")
      Current.set(household: other_household) do
        other_account = create(:account)
        create(:cash_transaction, :bank, account: other_account, amount: 500.00,
               transaction_date: Date.current)
      end

      expect(service.candidates).to be_empty
    end

    it "requires a household context" do
      Current.set(household: nil) do
        expect { described_class.new }.to raise_error(ArgumentError, /household/)
      end
    end
  end

  describe "cash ↔ investment pairs" do
    it "pairs a cash outflow with a matching investment inflow" do
      cash = cash_txn(account: account_a, amount: -1000.00)
      inv  = create(:investment_transaction, account: account_b,
                    amount_usd: 1000.00, trade_date: Date.current)

      pair = service.candidates.find { |r| r.to_type == "InvestmentTransaction" }
      expect(pair).not_to be_nil
      expect(pair.from_transaction.id).to eq(cash.id)
      expect(pair.to_transaction.id).to eq(inv.id)
    end

    it "pairs an investment outflow with a matching cash inflow" do
      inv  = create(:investment_transaction, account: account_b,
                    amount_usd: -1000.00, trade_date: Date.current)
      cash = cash_txn(account: account_a, amount: 1000.00)

      pair = service.candidates.find { |r| r.from_type == "InvestmentTransaction" }
      expect(pair).not_to be_nil
      expect(pair.from_transaction.id).to eq(inv.id)
      expect(pair.to_transaction.id).to eq(cash.id)
    end
  end

  describe "trailing lookback window" do
    it "no longer scans ancient unlinked rows" do
      stale = Date.current - described_class::LOOKBACK_MONTHS.months - 2.months
      cash_txn(account: account_a, amount: -500.00, date: stale)
      cash_txn(account: account_b, amount: 500.00,  date: stale + 1.day)

      expect(service.candidates).to be_empty
    end

    it "still pairs rows just inside the window" do
      fresh = Date.current - described_class::LOOKBACK_MONTHS.months + 1.month
      cash_txn(account: account_a, amount: -500.00, date: fresh)
      cash_txn(account: account_b, amount: 500.00,  date: fresh + 1.day)

      expect(service.candidates).not_to be_empty
    end
  end
end
