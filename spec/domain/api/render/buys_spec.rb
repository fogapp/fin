require "rails_helper"

RSpec.describe Api::Render::Buys do
  def renderer
    described_class.new(params: ActionController::Parameters.new)
  end

  describe "#index" do
    it "returns expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[totals monthly_volume top_securities by_account cumulative_invested transactions])
    end

    it "counts purchases and sums invested amounts" do
      tt = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: tt, amount_usd: 500.0)
      create(:investment_transaction, transaction_type: tt, amount_usd: 300.0)

      result = renderer.index
      expect(result[:totals][:count]).to eq(2)
      expect(result[:totals][:all_time]).to be_within(0.01).of(800.0)
    end

    it "excludes non-purchase transaction types" do
      create(:investment_transaction, transaction_type: create(:transaction_type, :sale))
      result = renderer.index
      expect(result[:totals][:count]).to eq(0)
    end

    it "includes transactions with serialized fields" do
      tt = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: tt)
      result = renderer.index
      expect(result[:transactions].first.keys).to include(:trade_date, :security_ticker, :account_name)
    end
  end
end
