require "rails_helper"

RSpec.describe InvestmentTransaction, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:security).optional }
    it { is_expected.to belong_to(:transaction_type) }
  end

  describe "validations" do
    subject { build(:investment_transaction) }

    it { is_expected.to validate_presence_of(:trade_date) }
    it { is_expected.to validate_presence_of(:source_row_hash) }
    it { is_expected.to validate_uniqueness_of(:source_row_hash) }
  end

  describe "category constants" do
    it "freezes INCOME_CATEGORIES" do
      expect(InvestmentTransaction::INCOME_CATEGORIES).to be_frozen
      expect(InvestmentTransaction::INCOME_CATEGORIES).to include("Dividend", "Foreign Dividend", "Interest", "Municipal Interest")
    end

    it "freezes DIVIDEND_CATEGORIES" do
      expect(InvestmentTransaction::DIVIDEND_CATEGORIES).to be_frozen
      expect(InvestmentTransaction::DIVIDEND_CATEGORIES).to contain_exactly("Dividend", "Foreign Dividend")
    end
  end

  describe "scopes" do
    let(:account)  { create(:account) }
    let(:security) { create(:security) }

    describe ".recent" do
      it "orders by trade_date desc, then id desc" do
        old   = create(:investment_transaction, account: account, trade_date: Date.new(2025, 1, 1))
        newer = create(:investment_transaction, account: account, trade_date: Date.new(2025, 6, 1))
        same_day_earlier = create(:investment_transaction, account: account, trade_date: Date.new(2025, 6, 1))

        expect(InvestmentTransaction.recent.first).to be_one_of(newer, same_day_earlier)
        expect(InvestmentTransaction.recent.last).to eq(old)
        expect(InvestmentTransaction.recent.pluck(:id).first(2)).to eq([ newer.id, same_day_earlier.id ].sort.reverse)
      end
    end

    describe ".income" do
      it "matches all INCOME_CATEGORIES" do
        div = create(:transaction_type, :dividend)
        intl = create(:transaction_type, :foreign_dividend)
        intr = create(:transaction_type, :interest)
        purch = create(:transaction_type, :purchase)

        income_txns = [
          create(:investment_transaction, account: account, transaction_type: div),
          create(:investment_transaction, account: account, transaction_type: intl),
          create(:investment_transaction, account: account, transaction_type: intr)
        ]
        create(:investment_transaction, account: account, transaction_type: purch)

        expect(InvestmentTransaction.income).to match_array(income_txns)
      end
    end

    describe ".dividends" do
      it "matches only Dividend and Foreign Dividend" do
        div = create(:transaction_type, :dividend)
        fd  = create(:transaction_type, :foreign_dividend)
        intr = create(:transaction_type, :interest)

        d1 = create(:investment_transaction, account: account, transaction_type: div)
        d2 = create(:investment_transaction, account: account, transaction_type: fd)
        create(:investment_transaction, account: account, transaction_type: intr)

        expect(InvestmentTransaction.dividends).to match_array([ d1, d2 ])
      end
    end

    describe ".purchases" do
      it "matches Purchase category" do
        purch = create(:transaction_type, :purchase)
        sale  = create(:transaction_type, :sale)

        p = create(:investment_transaction, account: account, transaction_type: purch)
        create(:investment_transaction, account: account, transaction_type: sale)

        expect(InvestmentTransaction.purchases).to contain_exactly(p)
      end
    end

    describe ".sales" do
      it "matches Sale category" do
        sale  = create(:transaction_type, :sale)
        purch = create(:transaction_type, :purchase)

        s = create(:investment_transaction, account: account, transaction_type: sale)
        create(:investment_transaction, account: account, transaction_type: purch)

        expect(InvestmentTransaction.sales).to contain_exactly(s)
      end
    end
  end

  RSpec::Matchers.define :be_one_of do |*expected|
    match { |actual| expected.include?(actual) }
  end
end
