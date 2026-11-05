require "rails_helper"

RSpec.describe Api::Render::CashTransaction do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns all transactions sorted by date descending" do
      t1 = create(:cash_transaction, :bank, :debit, transaction_date: 3.days.ago)
      t2 = create(:cash_transaction, :bank, :debit, transaction_date: 1.day.ago)

      result = renderer.index
      expect(result.map { |t| t[:id] }).to eq([ t2.id, t1.id ])
    end

    it "filters by source" do
      create(:cash_transaction, :bank, :debit)
      cc = create(:cash_transaction, :credit_card, :sale)

      result = renderer(source: "credit_card").index
      expect(result.map { |t| t[:id] }).to contain_exactly(cc.id)
    end

    it "filters by start_date" do
      create(:cash_transaction, :bank, :debit, transaction_date: 10.days.ago)
      recent = create(:cash_transaction, :bank, :debit, transaction_date: 2.days.ago)

      result = renderer(start_date: 5.days.ago.to_date.to_s).index
      expect(result.map { |t| t[:id] }).to contain_exactly(recent.id)
    end

    it "filters by end_date" do
      old = create(:cash_transaction, :bank, :debit, transaction_date: 10.days.ago)
      create(:cash_transaction, :bank, :debit, transaction_date: 2.days.ago)

      result = renderer(end_date: 5.days.ago.to_date.to_s).index
      expect(result.map { |t| t[:id] }).to contain_exactly(old.id)
    end

    it "enforces a default limit when the client omits one" do
      stub_const("Api::Render::CashTransaction::MAX_LIMIT", 2)
      create_list(:cash_transaction, 3, :bank, :debit)

      expect(renderer.index.length).to eq(2)
    end

    it "clamps an oversized limit param to the maximum" do
      stub_const("Api::Render::CashTransaction::MAX_LIMIT", 2)
      create_list(:cash_transaction, 3, :bank, :debit)

      expect(renderer(limit: "999").index.length).to eq(2)
    end

    it "still pages with limit/offset" do
      t1 = create(:cash_transaction, :bank, :debit, transaction_date: 3.days.ago)
      t2 = create(:cash_transaction, :bank, :debit, transaction_date: 1.day.ago)

      result = renderer(limit: "1", offset: "1").index
      expect(result.map { |t| t[:id] }).to eq([ t1.id ])
      expect(renderer(limit: "1").index.map { |t| t[:id] }).to eq([ t2.id ])
    end

    it "filters by merchant_id" do
      merchant = create(:merchant)
      matched = create(:cash_transaction, :credit_card, :sale, merchant: merchant)
      create(:cash_transaction, :credit_card, :sale)

      result = renderer(merchant_id: merchant.id).index
      expect(result.map { |t| t[:id] }).to contain_exactly(matched.id)
    end

    it "filters by category_id" do
      category = create(:category)
      matched = create(:cash_transaction, :credit_card, :sale, category: category)
      create(:cash_transaction, :credit_card, :sale)

      result = renderer(category_id: category.id).index
      expect(result.map { |t| t[:id] }).to contain_exactly(matched.id)
    end

    it "filters by account_id" do
      account = create(:account)
      matched = create(:cash_transaction, :bank, :debit, account: account)
      create(:cash_transaction, :bank, :debit)

      result = renderer(account_id: account.id).index
      expect(result.map { |t| t[:id] }).to contain_exactly(matched.id)
    end

    it "filters by transaction_type" do
      matched = create(:cash_transaction, :credit_card, :sale)
      create(:cash_transaction, :credit_card, :payment)

      result = renderer(transaction_type: "Sale").index
      expect(result.map { |t| t[:id] }).to contain_exactly(matched.id)
    end

    it "filters by tag_id" do
      tag = create(:tag)
      matched = create(:cash_transaction, :credit_card, :sale)
      matched.tags << tag
      create(:cash_transaction, :credit_card, :sale)

      result = renderer(tag_id: tag.id).index
      expect(result.map { |t| t[:id] }).to contain_exactly(matched.id)
    end
  end

  describe "#show" do
    it "returns the serialized transaction" do
      txn = create(:cash_transaction, :bank, :debit, description: "ACH PAYMENT")

      result = renderer(id: txn.id).show
      expect(result[:id]).to eq(txn.id)
      expect(result[:description]).to eq("ACH PAYMENT")
      expect(result[:source]).to eq("bank")
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes all expected fields" do
      txn = create(:cash_transaction, :bank, :debit)
      result = renderer.serialize(txn)
      expect(result.keys).to match_array(%i[
        id source transaction_date post_date description amount
        transaction_type category_id category_name category_parent_name merchant_id merchant_name
        account_id account_name balance memo tags transfer_id
        transfer_kind transfer_include_in_spend
        loan_id loan_name budget_excluded created_at updated_at
      ])
    end

    it "casts amount and balance to float" do
      txn = create(:cash_transaction, :bank, :debit, amount: -42.50, balance: 1000.0)
      result = renderer.serialize(txn)
      expect(result[:amount]).to be_a(Float)
      expect(result[:balance]).to be_a(Float)
    end
  end
end
