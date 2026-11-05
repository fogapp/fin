require "rails_helper"

RSpec.describe Api::Render::Category do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns categories sorted by name with transaction counts" do
      zebra = create(:category, name: "Zebra")
      apple = create(:category, name: "Apple")
      create(:cash_transaction, :credit_card, :sale, category: apple)
      create(:cash_transaction, :credit_card, :sale, category: apple)

      result = renderer.index
      expect(result.map { |c| c[:name] }).to eq([ "Apple", "Zebra" ])
      expect(result.find { |c| c[:name] == "Apple" }[:transaction_count]).to eq(2)
      expect(result.find { |c| c[:name] == "Zebra" }[:transaction_count]).to eq(0)
    end
  end

  describe "#show" do
    it "includes totals, by_merchant breakdown, and monthly_spend" do
      category = create(:category)
      merchant = create(:merchant)
      create(:cash_transaction, :credit_card, :sale, category: category, merchant: merchant, amount: -10.0)
      create(:cash_transaction, :credit_card, :return, category: category, amount: 5.0)

      result = renderer(id: category.id).show

      expect(result[:id]).to eq(category.id)
      expect(result[:total_count]).to eq(2)
      # total_spend is spend_like, which nets returns against sales: -(-10 + 5) = 5
      expect(result[:total_spend]).to eq(5.0)
      expect(result[:total_returns]).to eq(5.0)
      expect(result[:by_merchant]).to be_a(Hash)
      expect(result[:monthly_spend]).to be_a(Hash)
    end

    it "adds up to the same number as the cashflow category breakdown" do
      parent   = create(:category, name: "Food")
      sub      = create(:category, name: "Dining", parent: parent)
      excluded = create(:merchant, excluded: true)
      date     = Date.current.beginning_of_month

      create(:cash_transaction, :credit_card, :sale, category: parent, amount: -30, transaction_date: date)
      create(:cash_transaction, :credit_card, :sale, category: sub, amount: -20, transaction_date: date - 1.month)
      create(:cash_transaction, :credit_card, :return, category: sub, amount: 5, transaction_date: date)
      create(:cash_transaction, :bank, category: parent, amount: -40, transaction_date: date)
      # Neither of these is spend anywhere in the app.
      create(:cash_transaction, :credit_card, :payment, category: parent, amount: 300, transaction_date: date)
      create(:cash_transaction, :credit_card, :sale, category: parent, merchant: excluded, amount: -99, transaction_date: date)

      result    = renderer(id: parent.id).show
      breakdown = Api::Render::Cashflow.new(params: ActionController::Parameters.new(from: (date - 1.month).to_s))
                                        .spend_breakdown
      cashflow_total = breakdown[:category][:months].values.sum { |m| m.fetch(parent.id.to_s, 0.0) }

      expect(result[:total_spend]).to eq(85.0)
      expect(result[:total_spend]).to eq(cashflow_total)
      expect(result[:subcategories].first[:total_spend]).to eq(15.0)
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes id and name" do
      category = create(:category, name: "Dining")
      expect(renderer.serialize(category)).to include(id: category.id, name: "Dining")
    end
  end
end
