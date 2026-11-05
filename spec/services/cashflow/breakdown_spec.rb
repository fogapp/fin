require "rails_helper"

RSpec.describe Cashflow::Breakdown do
  describe ".ranked" do
    let(:account)   { create(:account) }
    let(:groceries) { create(:category, name: "Groceries") }
    let(:travel)    { create(:category, name: "Travel") }

    def rank
      described_class.ranked(
        CashTransaction.spend_like,
        id_expr: "cash_transactions.category_id", name_expr: "categories.name", months: 1
      )
    end

    before do
      allow(CashTransaction).to receive(:spend_like).and_wrap_original { |m| m.call.joins(:category) }
    end

    it "nets returns out of a category instead of adding them" do
      create(:cash_transaction, :credit_card, :sale,   account: account, category: groceries, amount: -100)
      create(:cash_transaction, :credit_card, :return, account: account, category: groceries, amount: 30)

      expect(rank).to contain_exactly(include(id: groceries.id, amount: 70.0, largest: 100.0))
    end

    it "drops a category whose returns cover its charges" do
      create(:cash_transaction, :credit_card, :sale,   account: account, category: groceries, amount: -50)
      create(:cash_transaction, :credit_card, :sale,   account: account, category: travel,    amount: -40)
      create(:cash_transaction, :credit_card, :return, account: account, category: travel,    amount: 40)

      expect(rank.map { |r| r[:id] }).to eq([ groceries.id ])
    end
  end
end
