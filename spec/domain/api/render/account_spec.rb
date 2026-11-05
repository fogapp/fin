require "rails_helper"

RSpec.describe Api::Render::Account do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns accounts ordered by broker name then account name" do
      b1 = create(:broker, name: "Zebra")
      b2 = create(:broker, name: "Alpha")
      create(:account, broker: b1, name: "Z Account")
      create(:account, broker: b2, name: "A Account")

      result = renderer.index
      expect(result.map { |a| a[:name] }).to eq([ "A Account", "Z Account" ])
    end

    it "includes cash_transaction_count, investment_transaction_count, portfolio_value, and latest_transaction_date" do
      account = create(:account)
      create(:cash_transaction, :bank, :debit, account: account, transaction_date: 5.days.ago.to_date)
      create(:cash_transaction, :bank, :debit, account: account, transaction_date: 2.days.ago.to_date)

      result = renderer.index.find { |a| a[:id] == account.id }
      expect(result[:cash_transaction_count]).to eq(2)
      expect(result[:investment_transaction_count]).to eq(0)
      expect(result[:portfolio_value]).to eq(0.0)
      expect(result[:latest_transaction_date]).to eq(2.days.ago.to_date)
    end
  end

  describe "#show" do
    it "returns the serialized account" do
      account = create(:account)
      result = renderer(id: account.id).show
      expect(result[:id]).to eq(account.id)
      expect(result[:broker_name]).to eq(account.broker.name)
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes expected fields" do
      account = create(:account)
      result = renderer.serialize(account)
      expect(result.keys).to match_array(%i[id name account_number account_type broker_id broker_name balance balance_currency balance_usd plaid_item_id hidden kind tax_treatment])
    end
  end
end
