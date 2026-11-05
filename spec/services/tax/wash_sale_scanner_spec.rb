require "rails_helper"

RSpec.describe Tax::WashSaleScanner do
  let(:household) { Current.household }
  let(:year)      { 2026 }

  let!(:tt_sale)     { create(:transaction_type, :sale) }
  let!(:tt_purchase) { create(:transaction_type, :purchase) }

  let!(:brokerage) { create(:account, name: "Brokerage") }
  let!(:other_brokerage) { create(:account, name: "Other Brokerage") }
  let!(:ira)       { create(:account, name: "Roth", tax_treatment: "roth_ira") }

  let!(:security) { create(:security, ticker: "AAA", name: "Alpha Corp") }

  subject(:findings) { described_class.new(household: household, year: year).findings }

  def sale(account:, security:, date:, short: 0, long: 0)
    create(:investment_transaction, account: account, transaction_type: tt_sale,
           security: security, trade_date: date, gl_short_usd: short, gl_long_usd: long)
  end

  def purchase(account:, security:, date:)
    create(:investment_transaction, account: account, transaction_type: tt_purchase,
           security: security, trade_date: date)
  end

  it "matches a loss sale against a repurchase in a different account within 30 days" do
    sale(account: brokerage, security: security, date: Date.new(year, 5, 1), short: -400)
    purchase(account: other_brokerage, security: security, date: Date.new(year, 5, 20))

    expect(findings.sole).to include(
      security_label:   "AAA",
      sale_date:        Date.new(year, 5, 1),
      sale_account:     "Brokerage",
      loss:             -400.0,
      purchase_date:    Date.new(year, 5, 20),
      purchase_account: "Other Brokerage",
      permanent:        false
    )
  end

  it "flags repurchases inside retirement accounts as permanent disallowance" do
    sale(account: brokerage, security: security, date: Date.new(year, 5, 1), short: -400)
    purchase(account: ira, security: security, date: Date.new(year, 5, 10))

    expect(findings.sole).to include(purchase_account: "Roth", permanent: true)
  end

  it "matches purchases up to 30 days BEFORE the sale (the window is two-sided)" do
    sale(account: brokerage, security: security, date: Date.new(year, 5, 1), long: -250)
    purchase(account: brokerage, security: security, date: Date.new(year, 4, 15))

    expect(findings.sole).to include(purchase_date: Date.new(year, 4, 15), loss: -250.0)
  end

  it "produces one finding per matching purchase" do
    sale(account: brokerage, security: security, date: Date.new(year, 5, 1), short: -400)
    purchase(account: brokerage, security: security, date: Date.new(year, 5, 5))
    purchase(account: ira, security: security, date: Date.new(year, 5, 15))

    expect(findings.length).to eq(2)
    expect(findings.map { |f| f[:permanent] }).to eq([ false, true ])
  end

  it "finds nothing for gains, distant purchases, other securities, or other households" do
    # Net gain — not a loss sale.
    sale(account: brokerage, security: security, date: Date.new(year, 2, 1), short: -100, long: 500)
    purchase(account: brokerage, security: security, date: Date.new(year, 2, 10))

    # Loss, but the repurchase is 31 days out.
    sale(account: brokerage, security: security, date: Date.new(year, 7, 1), short: -400)
    purchase(account: brokerage, security: security, date: Date.new(year, 8, 1))

    # Loss with a repurchase of a DIFFERENT security.
    other_security = create(:security, ticker: "BBB")
    sale(account: brokerage, security: security, date: Date.new(year, 9, 1), short: -400)
    purchase(account: brokerage, security: other_security, date: Date.new(year, 9, 5))

    # Another household's matching pair is invisible.
    other = create(:household)
    Current.set(household: other) do
      other_account = create(:account, name: "Elsewhere")
      sale(account: other_account, security: security, date: Date.new(year, 5, 1), short: -400)
      purchase(account: other_account, security: security, date: Date.new(year, 5, 5))
    end

    expect(findings).to be_empty
  end

  it "ignores loss sales without a security" do
    create(:investment_transaction, account: brokerage, transaction_type: tt_sale,
           security: nil, trade_date: Date.new(year, 5, 1), gl_short_usd: -400)
    purchase(account: brokerage, security: security, date: Date.new(year, 5, 5))

    expect(findings).to be_empty
  end
end
