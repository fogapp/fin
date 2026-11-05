require "rails_helper"

RSpec.describe Api::Render::Sells do
  def renderer
    described_class.new(params: ActionController::Parameters.new)
  end

  describe "#index" do
    it "returns expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[totals monthly_volume monthly_gl top_securities by_account cumulative_realized transactions])
    end

    it "sums proceeds and realized gain/loss" do
      tt = create(:transaction_type, :sale)
      create(:investment_transaction, transaction_type: tt, amount_usd: 1000.0, gl_short_usd: 50.0, gl_long_usd: 100.0)

      result = renderer.index
      expect(result[:totals][:proceeds]).to be_within(0.01).of(1000.0)
      expect(result[:totals][:realized_short]).to be_within(0.01).of(50.0)
      expect(result[:totals][:realized_long]).to be_within(0.01).of(100.0)
      expect(result[:totals][:realized_net]).to be_within(0.01).of(150.0)
    end
  end
end
