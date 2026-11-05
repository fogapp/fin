require "rails_helper"

RSpec.describe Api::Render::Tag do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns all tags sorted by name with transaction_count and total_spend" do
      zebra = create(:tag, name: "zebra")
      apple = create(:tag, name: "apple")
      txn = create(:cash_transaction, :credit_card, :sale, amount: -25.0)
      txn.tags << apple

      result = renderer.index
      expect(result.map { |t| t[:name] }).to eq([ "apple", "zebra" ])
      expect(result.find { |t| t[:name] == "apple" }[:transaction_count]).to eq(1)
      expect(result.find { |t| t[:name] == "apple" }[:total_spend]).to eq(25.0)
      expect(result.find { |t| t[:name] == "zebra" }[:transaction_count]).to eq(0)
      expect(result.find { |t| t[:name] == "zebra" }[:total_spend]).to eq(0.0)
    end
  end

  describe "#show" do
    it "includes totals and by_category breakdown" do
      category = create(:category, name: "Dining")
      tag      = create(:tag)
      txn      = create(:cash_transaction, :credit_card, :sale, amount: -15.0, category: category)
      txn.tags << tag

      result = renderer(id: tag.id).show
      expect(result[:id]).to eq(tag.id)
      expect(result[:total_count]).to eq(1)
      expect(result[:total_spend]).to eq(15.0)
      expect(result[:by_category]).to include("Dining")
    end

    it "counts spend with the shared spend_like definition" do
      tag = create(:tag)
      create(:cash_transaction, :bank, amount: -40.0).tags << tag
      create(:cash_transaction, :credit_card, :sale, amount: -10.0).tags << tag
      create(:cash_transaction, :credit_card, :payment, amount: 300.0).tags << tag

      result = renderer(id: tag.id).show
      expect(result[:total_count]).to eq(3)
      expect(result[:total_spend]).to eq(50.0)
      expect(renderer.index.find { |t| t[:id] == tag.id }[:total_spend]).to eq(50.0)
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "returns id and name" do
      tag = create(:tag, name: "groceries")
      expect(renderer.serialize(tag)).to eq({ id: tag.id, name: "groceries" })
    end
  end
end
