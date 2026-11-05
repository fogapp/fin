require "rails_helper"

RSpec.describe InvestmentLots::GenerateFromTransactions do
  let(:security)       { create(:security) }
  let(:account)        { create(:account) }
  let(:other_account)  { create(:account) }
  let(:purchase_type)  { create(:transaction_type, :purchase) }
  let(:sale_type)      { create(:transaction_type, :sale) }

  def purchase(account:, qty:, cost:, date: Date.new(2026, 1, 1), commissions: 0.0)
    create(:investment_transaction, security: security, account: account,
           transaction_type: purchase_type, trade_date: date,
           quantity: qty, amount_usd: cost, cost_usd: cost, commissions_usd: commissions)
  end

  def sale(account:, qty:, date: Date.new(2026, 6, 1))
    create(:investment_transaction, security: security, account: account,
           transaction_type: sale_type, trade_date: date,
           quantity: -qty, amount_usd: qty * 100, cost_usd: qty * 100)
  end

  describe "#preview" do
    it "returns a serialized lot per surviving purchase without persisting" do
      purchase(account: account, qty: 10, cost: 1000)

      service = described_class.new(security_id: security.id)
      result  = service.preview

      expect(InvestmentLot.count).to eq(0)
      expect(result.length).to eq(1)
      expect(result.first).to include(account_id: account.id, quantity: 10.0, cost_basis: 1000.0)
      expect(result.first[:unit_cost]).to eq(100.0)
      expect(result.first[:acquired_date]).to eq("2026-01-01")
    end

    it "is empty when there are no purchases" do
      expect(described_class.new(security_id: security.id).preview).to eq([])
    end

    it "groups by account so FIFO is applied per account" do
      purchase(account: account,       qty: 5,  cost: 500)
      purchase(account: other_account, qty: 10, cost: 2000)

      result = described_class.new(security_id: security.id).preview
      expect(result.length).to eq(2)
      by_account = result.index_by { |r| r[:account_id] }
      expect(by_account[account.id][:quantity]).to       eq(5.0)
      expect(by_account[other_account.id][:quantity]).to eq(10.0)
    end

    it "applies FIFO: oldest lots are consumed by sales first" do
      purchase(account: account, qty: 5,  cost: 500,  date: Date.new(2026, 1, 1))
      purchase(account: account, qty: 10, cost: 2000, date: Date.new(2026, 3, 1))
      sale(account: account, qty: 5,  date: Date.new(2026, 6, 1))

      result = described_class.new(security_id: security.id).preview
      # Older 5-share lot fully consumed; newer 10-share lot remains.
      expect(result.length).to eq(1)
      expect(result.first[:quantity]).to   eq(10.0)
      expect(result.first[:cost_basis]).to eq(2000.0)
    end

    it "pro-rates cost when a lot is partially consumed" do
      purchase(account: account, qty: 10, cost: 1000, date: Date.new(2026, 1, 1))
      sale(account: account, qty: 4, date: Date.new(2026, 6, 1))

      result = described_class.new(security_id: security.id).preview
      expect(result.first[:quantity]).to   eq(6.0)
      expect(result.first[:cost_basis]).to eq(600.0)
      expect(result.first[:unit_cost]).to  eq(100.0)
    end

    it "treats every imported purchase as a surviving lot when sales exceed imported purchases" do
      purchase(account: account, qty: 10, cost: 1000)
      sale(account: account, qty: 15)

      result = described_class.new(security_id: security.id).preview
      expect(result.length).to eq(1)
      expect(result.first[:quantity]).to eq(10.0)
    end

    it "falls back to amount + commissions when cost_usd is missing" do
      create(:investment_transaction, security: security, account: account,
             transaction_type: purchase_type,
             trade_date: Date.new(2026, 1, 1),
             quantity: 10, amount_usd: 1000.0, cost_usd: nil, commissions_usd: 5.0)

      result = described_class.new(security_id: security.id).preview
      expect(result.first[:cost_basis]).to eq(1005.0)
    end
  end

  describe "#commit!" do
    it "persists lots with replace: false when no lots exist" do
      purchase(account: account, qty: 10, cost: 1000)

      service = described_class.new(security_id: security.id)
      expect { service.commit!(replace: false) }
        .to change(InvestmentLot, :count).by(1)
    end

    it "destroys existing lots first with replace: true" do
      existing = create(:investment_lot, security: security)
      purchase(account: account, qty: 10, cost: 1000)

      described_class.new(security_id: security.id).commit!(replace: true)
      expect(InvestmentLot.exists?(existing.id)).to be false
      expect(InvestmentLot.where(security_id: security.id).count).to eq(1)
    end

    it "keeps existing lots intact with replace: false" do
      existing = create(:investment_lot, security: security)
      purchase(account: account, qty: 10, cost: 1000)

      described_class.new(security_id: security.id).commit!(replace: false)
      expect(InvestmentLot.exists?(existing.id)).to be true
      expect(InvestmentLot.where(security_id: security.id).count).to eq(2)
    end
  end
end
