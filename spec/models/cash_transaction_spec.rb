require "rails_helper"

RSpec.describe CashTransaction, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to belong_to(:merchant).optional }
    it { is_expected.to belong_to(:category).optional }
    it { is_expected.to have_many(:cash_transaction_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:cash_transaction_tags) }
  end

  describe "validations" do
    subject { build(:cash_transaction) }

    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:transaction_date) }
    it { is_expected.to validate_presence_of(:source_row_hash) }
    it { is_expected.to validate_uniqueness_of(:source_row_hash) }

    context "balance" do
      it "is optional for bank transactions (Plaid syncs have no per-transaction balance)" do
        txn = build(:cash_transaction, :bank, balance: nil)
        expect(txn).to be_valid
      end

      it "is optional for credit card transactions" do
        txn = build(:cash_transaction, :credit_card, balance: nil)
        expect(txn).to be_valid
      end
    end
  end

  describe "enum :source" do
    it "stores 'bank' as the string value" do
      txn = create(:cash_transaction, :bank)
      expect(txn.reload.read_attribute(:source)).to eq("bank")
    end

    it "stores 'credit_card' as the string value" do
      txn = create(:cash_transaction, :credit_card)
      expect(txn.reload.read_attribute(:source)).to eq("credit_card")
    end

    it "recognizes source_bank? predicate" do
      expect(build(:cash_transaction, :bank)).to be_source_bank
    end

    it "recognizes source_credit_card? predicate" do
      expect(build(:cash_transaction, :credit_card)).to be_source_credit_card
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by transaction_date desc, then created_at desc" do
        old   = create(:cash_transaction, transaction_date: Date.new(2025, 1, 1))
        newer = create(:cash_transaction, transaction_date: Date.new(2025, 6, 1))

        expect(CashTransaction.recent.to_a).to eq([ newer, old ])
      end
    end

    describe ".source_bank / .source_credit_card" do
      it "filters by source" do
        bank = create(:cash_transaction, :bank)
        cc   = create(:cash_transaction, :credit_card)

        expect(CashTransaction.source_bank).to contain_exactly(bank)
        expect(CashTransaction.source_credit_card).to contain_exactly(cc)
      end
    end

    describe ".sales" do
      it "matches Sale transaction_type" do
        sale = create(:cash_transaction, :sale)
        create(:cash_transaction, :payment)

        expect(CashTransaction.sales).to contain_exactly(sale)
      end
    end

    describe ".returns" do
      it "matches Return transaction_type" do
        ret = create(:cash_transaction, :return)
        create(:cash_transaction, :sale)

        expect(CashTransaction.returns).to contain_exactly(ret)
      end
    end

    describe ".charges" do
      it "matches Sale and Return types" do
        sale = create(:cash_transaction, :sale)
        ret  = create(:cash_transaction, :return)
        create(:cash_transaction, :payment)

        expect(CashTransaction.charges).to match_array([ sale, ret ])
      end
    end
  end

  describe "#credit?" do
    it "is true for a positive amount only" do
      expect(build(:cash_transaction, amount: 50.00)).to be_credit
      expect(build(:cash_transaction, amount: -50.00)).not_to be_credit
    end
  end
end
