require "rails_helper"

RSpec.describe Api::Render::Merchant do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns merchants sorted by name with transaction counts" do
      zebra = create(:merchant, name: "Zebra")
      apple = create(:merchant, name: "Apple")
      create(:cash_transaction, :credit_card, :sale, merchant: apple)
      create(:cash_transaction, :credit_card, :sale, merchant: apple)

      result = renderer.index
      expect(result.map { |m| m[:name] }).to eq([ "Apple", "Zebra" ])
      expect(result.find { |m| m[:name] == "Apple" }[:transaction_count]).to eq(2)
      expect(result.find { |m| m[:name] == "Zebra" }[:transaction_count]).to eq(0)
    end
  end

  describe "#show" do
    it "includes merchant fields and monthly series" do
      merchant = create(:merchant)

      result = renderer(id: merchant.id).show

      expect(result[:id]).to eq(merchant.id)
      expect(result[:name]).to eq(merchant.name)
      expect(result).not_to have_key(:merchant_rules)
      expect(result).to have_key(:monthly_spend)
      expect(result).to have_key(:monthly_counts)
      expect(result).to have_key(:monthly_income)
    end

    it "charts spend with the shared spend_like definition (bank debits count, card payments don't)" do
      merchant = create(:merchant)
      date = Date.current.beginning_of_month
      create(:cash_transaction, :credit_card, :sale, merchant: merchant, amount: -40, transaction_date: date)
      create(:cash_transaction, :bank, merchant: merchant, amount: -60, transaction_date: date)
      create(:cash_transaction, :credit_card, merchant: merchant, amount: 500, transaction_date: date,
             transaction_type: CashTransaction::TransactionType::Payment.serialize)

      result = renderer(id: merchant.id).show
      expect(result[:monthly_spend][date.to_s]).to eq(100.0)
    end

    it "still charts an excluded merchant's own spend" do
      merchant = create(:merchant, excluded: true)
      date = Date.current.beginning_of_month
      create(:cash_transaction, :credit_card, :sale, merchant: merchant, amount: -25, transaction_date: date)

      result = renderer(id: merchant.id).show
      expect(result[:monthly_spend][date.to_s]).to eq(25.0)
      # The lift is scoped to this render — household totals still exclude it.
      expect(CashTransaction.spend_like.where(merchant_id: merchant.id)).to be_empty
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes expected fields" do
      merchant = create(:merchant)
      result = renderer.serialize(merchant)
      expect(result.keys).to match_array(%i[id name category_id category_name notes excluded])
    end
  end
end
