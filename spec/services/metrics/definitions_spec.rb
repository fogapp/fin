require "rails_helper"

RSpec.describe "Metrics definitions" do
  let(:this_month) { Date.current.beginning_of_month }
  let(:last_month) { this_month << 1 }

  describe Metrics::Definitions::CcTransactionCount do
    it "counts credit-card sales and returns, excluding payments and bank rows" do
      create(:cash_transaction, :credit_card, :sale,    transaction_date: this_month)
      create(:cash_transaction, :credit_card, :return,  transaction_date: this_month)
      create(:cash_transaction, :credit_card, :payment, transaction_date: this_month)
      create(:cash_transaction, :bank, :debit,          transaction_date: this_month)

      series = described_class.new.series(from: this_month, to: Date.current)
      expect(series[this_month]).to eq(2)
    end

    it "materializes months without transactions as zero" do
      create(:cash_transaction, :credit_card, :sale, transaction_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[this_month]).to eq(0)
    end
  end

  describe Metrics::Definitions::CcAvgTransaction do
    it "averages card charge volume over charge count, nil for empty months" do
      create(:cash_transaction, :credit_card, :sale, amount: -30.0, transaction_date: last_month)
      create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: last_month)
      # Payments don't count as charges
      create(:cash_transaction, :credit_card, :payment, amount: 80.0, transaction_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[last_month]).to eq(40.0)
      expect(series[this_month]).to be_nil
    end

    it "nets returns against sales" do
      create(:cash_transaction, :credit_card, :sale,   amount: -100.0, transaction_date: last_month)
      create(:cash_transaction, :credit_card, :return, amount: 20.0,   transaction_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[last_month]).to eq(40.0) # (100 - 20) / 2
    end
  end

  describe Metrics::Definitions::MonthlySpend do
    it "sums spend_like transactions negated, skipping transfers and excluded merchants" do
      create(:cash_transaction, :credit_card, :sale, amount: -40.0, transaction_date: this_month)
      create(:cash_transaction, :bank, :debit, amount: -60.0, transaction_date: this_month)
      transfer_txn = create(:cash_transaction, :bank, :transfer, amount: -500.0, transaction_date: this_month)
      transfer = create(:transfer, :confirmed, amount: 500.0,
                        from_transaction_id: transfer_txn.id, from_transaction_type: "CashTransaction",
                        counterparty_account_id: create(:account, kind: "external").id)
      transfer_txn.update!(transfer: transfer)

      excluded = create(:merchant, excluded: true)
      create(:cash_transaction, :credit_card, :sale, amount: -999.0, merchant: excluded, transaction_date: this_month)

      series = described_class.new.series(from: this_month, to: Date.current)
      expect(series[this_month]).to eq(100.0)
    end
  end

  describe Metrics::Definitions::SavingsRate do
    it "returns percentage points and nil for months without income" do
      create(:cash_transaction, :bank, :credit, amount: 1000.0, transaction_date: last_month)
      create(:cash_transaction, :credit_card, :sale, amount: -250.0, transaction_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[last_month]).to eq(75.0)
      expect(series[this_month]).to be_nil
    end
  end

  describe Metrics::Definitions::NetCashflow do
    it "computes income minus spend per month" do
      create(:cash_transaction, :bank, :credit, amount: 1000.0, transaction_date: last_month)
      create(:cash_transaction, :credit_card, :sale, amount: -300.0, transaction_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[last_month]).to eq(700.0)
    end
  end

  describe Metrics::Definitions::DividendIncome do
    it "sums investment income by trade month" do
      create(:investment_transaction,
             transaction_type: create(:transaction_type, :dividend),
             income_usd: 12.5, trade_date: last_month)
      create(:investment_transaction,
             transaction_type: create(:transaction_type, :purchase),
             income_usd: 999.0, trade_date: last_month)

      series = described_class.new.series(from: last_month, to: Date.current)
      expect(series[last_month]).to eq(12.5)
    end
  end
end
