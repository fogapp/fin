require "rails_helper"

RSpec.describe Api::Render::Dividends do
  def renderer
    described_class.new(params: ActionController::Parameters.new)
  end

  describe "#index" do
    it "returns expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[totals monthly_dividends top_securities by_account cumulative_dividends transactions])
    end

    it "sums amounts across dividend transaction types" do
      create(:investment_transaction, transaction_type: create(:transaction_type, :dividend), amount_usd: 25.0)
      create(:investment_transaction, transaction_type: create(:transaction_type, :foreign_dividend), amount_usd: 10.0)
      create(:investment_transaction, transaction_type: create(:transaction_type, :purchase), amount_usd: 999.0)

      result = renderer.index
      expect(result[:totals][:lifetime]).to be_within(0.01).of(35.0)
      expect(result[:totals][:count]).to eq(2)
    end
  end
end
