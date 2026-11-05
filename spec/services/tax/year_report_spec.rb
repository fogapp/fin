require "rails_helper"

RSpec.describe Tax::YearReport do
  let(:household) { Current.household }
  let(:year)      { 2026 }

  # Transaction types (unique codes, so one of each).
  let!(:tt_sale)      { create(:transaction_type, :sale) }
  let!(:tt_purchase)  { create(:transaction_type, :purchase) }
  let!(:tt_dividend)  { create(:transaction_type, :dividend) }
  let!(:tt_interest)  { create(:transaction_type, :interest) }
  let!(:tt_other)     { create(:transaction_type) }

  # Accounts across tax treatments.
  let!(:brokerage)     { create(:account, name: "Brokerage") }
  let!(:checking)      { create(:account, name: "Checking") }
  let!(:ira)           { create(:account, name: "IRA", tax_treatment: "traditional_ira") }
  let!(:t401k)         { create(:account, name: "Linked 401k", tax_treatment: "traditional_401k") }
  let!(:external_401k) { create(:account, name: "External 401k", kind: "external", broker: nil, tax_treatment: "traditional_401k") }

  let!(:sec_a) { create(:security, ticker: "AAA") }
  let!(:sec_b) { create(:security, ticker: "BBB") }
  let!(:sec_c) { create(:security, ticker: "CCC") }

  let!(:profile) do
    create(:tax_profile, tax_year: year, filing_status: "single", projected_wages: 300_000,
           other_ordinary_income: 1_000, prior_year_total_tax: 40_000, prior_year_agi: 200_000,
           ytd_withholding_federal: 50_000, ytd_withholding_state: 20_000)
  end

  before do
    # --- Realized gains (sales carry the gl columns) -----------------------
    create(:investment_transaction, account: brokerage, transaction_type: tt_sale, security: sec_a,
           trade_date: Date.new(year, 2, 10), gl_short_usd: -500, gl_long_usd: 2_000, amount_usd: 10_000)
    create(:investment_transaction, account: brokerage, transaction_type: tt_sale, security: sec_b,
           trade_date: Date.new(year, 3, 5), gl_short_usd: 0, gl_long_usd: 1_000, amount_usd: 4_000)
    # Prior-year sale must not count.
    create(:investment_transaction, account: brokerage, transaction_type: tt_sale, security: sec_a,
           trade_date: Date.new(year - 1, 12, 20), gl_short_usd: 0, gl_long_usd: 9_999)

    # --- Wash sale: loss sale + IRA repurchase 9 days later ----------------
    create(:investment_transaction, account: brokerage, transaction_type: tt_sale, security: sec_c,
           trade_date: Date.new(year, 5, 1), gl_short_usd: -400, gl_long_usd: 0, amount_usd: 1_000)
    create(:investment_transaction, account: ira, transaction_type: tt_purchase, security: sec_c,
           trade_date: Date.new(year, 5, 10), quantity: 5)

    # --- Dividend + interest income ----------------------------------------
    create(:investment_transaction, account: brokerage, transaction_type: tt_dividend, security: sec_a,
           trade_date: Date.new(year, 6, 1), income_usd: 800)
    create(:investment_transaction, account: brokerage, transaction_type: tt_interest, security: nil,
           trade_date: Date.new(year, 6, 15), income_usd: 200)

    # --- Equity comp: ISO + NSO exercises, RSU settlement, nil-price skip --
    company = create(:equity_company, name: "Rocketry")
    iso  = create(:equity_grant, :fully_vested, equity_company: company, grant_type: "iso",
                  strike_price: 1.25, quantity: 4_800, grant_date: Date.new(year - 1, 1, 1))
    nso  = create(:equity_grant, :fully_vested, equity_company: company, grant_type: "nso",
                  strike_price: 1.25, quantity: 4_800, grant_date: Date.new(year - 1, 1, 1))
    rsu  = create(:equity_grant, :rsu, :fully_vested, equity_company: company,
                  quantity: 1_000, grant_date: Date.new(year - 1, 1, 1))
    create(:equity_grant_event, equity_grant: iso, kind: "exercise",
           occurred_on: Date.new(year, 3, 1), quantity: 100, share_price: 5)
    create(:equity_grant_event, equity_grant: nso, kind: "exercise",
           occurred_on: Date.new(year, 4, 1), quantity: 100, share_price: 5)
    create(:equity_grant_event, equity_grant: rsu, kind: "settlement",
           occurred_on: Date.new(year, 5, 15), quantity: 10, share_price: 20)
    create(:equity_grant_event, equity_grant: nso, kind: "exercise",
           occurred_on: Date.new(year, 6, 1), quantity: 10, share_price: nil)

    # --- Contributions: pair transfer into the linked 401k, one-sided to the
    # external 401k, and an out-of-year transfer that must not count. -------
    to_401k = create(:investment_transaction, account: t401k, transaction_type: tt_other,
                     security: nil, trade_date: Date.new(year, 3, 15), amount_usd: 10_000)
    from_checking = create(:cash_transaction, :bank, account: checking, amount: -10_000,
                           transaction_date: Date.new(year, 3, 14))
    create(:transfer, :confirmed, amount: 10_000,
           from_transaction_id: from_checking.id, from_transaction_type: "CashTransaction",
           to_transaction_id: to_401k.id, to_transaction_type: "InvestmentTransaction")

    one_sided_source = create(:cash_transaction, :bank, account: checking, amount: -5_000,
                              transaction_date: Date.new(year, 5, 1))
    create(:transfer, :confirmed, amount: 5_000,
           from_transaction_id: one_sided_source.id, from_transaction_type: "CashTransaction",
           counterparty_account_id: external_401k.id)

    stale = create(:investment_transaction, account: t401k, transaction_type: tt_other,
                   security: nil, trade_date: Date.new(year - 1, 12, 1), amount_usd: 7_000)
    create(:transfer, :confirmed, amount: 7_000,
           to_transaction_id: stale.id, to_transaction_type: "InvestmentTransaction",
           counterparty_account_id: checking.id)

    # --- Charitable gift with a received receipt ---------------------------
    giving = create(:category, name: "Giving", charitable: true)
    @gift = create(:cash_transaction, source: "credit_card", transaction_type: "Sale",
                   account: checking, category: giving, amount: -300,
                   transaction_date: Date.new(year, 4, 2), description: "RED CROSS DONATION")
    create(:tax_checklist_item, tax_year: year, kind: "charitable_receipt",
           source_label: "Red Cross gift", status: "received", reference_id: @gift.id)

    # --- Mortgage: one prior-year payment (walks the balance), two in-year -
    loan = create(:loan, name: "Home Loan", original_principal: 100_000, interest_rate: 6.0,
                  term_months: 360, start_date: Date.new(year - 1, 11, 1), status: "active")
    [ Date.new(year - 1, 12, 1), Date.new(year, 1, 1), Date.new(year, 2, 1) ].each do |date|
      create(:cash_transaction, :bank, account: checking, loan: loan,
             amount: -599.55, transaction_date: date)
    end

    # --- Estimated payments + one adjustment of every kind -----------------
    create(:estimated_tax_payment, jurisdiction: "federal", paid_on: Date.new(year, 4, 10), amount: 5_000)
    create(:estimated_tax_payment, jurisdiction: "state",   paid_on: Date.new(year, 6, 1),  amount: 3_000)

    create(:tax_adjustment, kind: "income",       label: "K-1 income",   amount: 10_000)
    create(:tax_adjustment, kind: "deduction",    label: "Property tax", amount: 8_000)
    create(:tax_adjustment, kind: "credit",       label: "EV credit",    amount: 500)
    create(:tax_adjustment, kind: "payment",      label: "Extension payment", amount: 2_000)
    create(:tax_adjustment, kind: "contribution", label: "Payroll 401k", amount: 1_000, bucket: "401k")
  end

  subject(:report) { described_class.build(household: household, year: year) }

  it "assembles income facts: interest, dividends, realized gains, equity comp, adjustments" do
    income = report[:income]
    expect(income[:kind]).to eq("fact")
    expect(income[:interest]).to eq(200.0)
    expect(income[:dividends]).to eq(800.0)
    expect(income.dig(:wages, :amount)).to eq(300_000.0)
    expect(income.dig(:wages, :kind)).to eq("estimate")

    gains = income[:realized_gains]
    expect(gains[:short_term]).to eq(-900.0)
    expect(gains[:long_term]).to eq(3_000.0)
    expect(gains[:total]).to eq(2_100.0)
    expect(gains[:by_security].map { |r| r[:label] }).to eq(%w[AAA BBB CCC])
    expect(gains[:by_security].first).to include(short_term: -500.0, long_term: 2_000.0, total: 1_500.0)

    equity = income[:equity_comp]
    expect(equity[:ordinary_income]).to eq(575.0)  # NSO 375 + RSU 200
    expect(equity[:iso_amt_spread]).to eq(375.0)
    expect(equity[:events].length).to eq(4)
    expect(equity[:events].count { |e| e[:skipped] }).to eq(1)
    expect(equity[:notes].join).to include("no share price")

    expect(income.dig(:adjustments, :total)).to eq(10_000.0)
    expect(income.dig(:adjustments, :items).sole).to include(label: "K-1 income")
  end

  it "assembles deductions: per-year mortgage interest, charitable with receipts, SALT, adjustments" do
    deductions = report[:deductions]

    mortgage = deductions[:mortgage_interest]
    # Amortization walk at 0.5%/mo: 500.00 (prior year, excluded) then 499.50 + 499.00 in-year.
    expect(mortgage[:total]).to eq(998.5)
    expect(mortgage[:loans].sole).to include(name: "Home Loan", interest_paid: 998.5)

    charitable = deductions[:charitable]
    expect(charitable[:total]).to eq(300.0)
    expect(charitable[:gifts].sole).to include(
      transaction_id: @gift.id, amount: 300.0, receipt: true, description: "RED CROSS DONATION"
    )

    expect(deductions[:salt]).to include(
      kind: "record", state_withholding: 20_000.0, state_estimated_payments: 3_000.0, amount: 23_000.0
    )
    expect(deductions.dig(:adjustments, :total)).to eq(8_000.0)
  end

  it "estimates liability by running the engines over assembled income, in parity with direct calls" do
    liability = report[:liability]
    expect(liability[:kind]).to eq("estimate")

    # other_ordinary = profile 1,000 + interest 200 + equity ordinary 575 + income adj 10,000
    # ltcg_qd        = max(long gains, 0) 3,000 + dividends 800
    expected_federal = Tax::Federal.new(
      tax_year: year, filing_status: Tax::FilingStatus::Single, wages: 300_000.0,
      other_ordinary: 11_775.0, ltcg_qd: 3_800.0,
      itemizing: false, salt_paid: 23_000.0, itemized_other: 0.0, iso_spread: 375.0
    ).call
    expected_california = Tax::California.new(
      tax_year: year, filing_status: Tax::FilingStatus::Single, wages: 300_000.0,
      other_ordinary: 11_775.0, ltcg_qd: 3_800.0, iso_spread: 375.0
    ).call

    expect(liability.dig(:federal, :regular_tax)).to eq(expected_federal[:regular_tax])
    expect(liability.dig(:federal, :amt)).to eq(expected_federal[:amt])
    expect(liability.dig(:federal, :total)).to eq((expected_federal[:regular_tax] + expected_federal[:amt]).round(2))
    expect(liability.dig(:state, :regular_tax)).to eq(expected_california[:regular_tax])

    total_income = 300_000.0 + 11_775.0 + 3_800.0
    expect(liability.dig(:federal, :effective_rate))
      .to eq((liability.dig(:federal, :total) / total_income).round(4))
    expect(liability.dig(:federal, :marginal_ordinary_rate)).to eq(0.35) # ordinary taxable ~$295k (single)

    # Withheld and paid: 50,000 withholding + 5,000 estimated + 2,000 payment adjustment.
    expect(liability.dig(:federal, :withheld_and_paid)).to eq(57_000.0)
    expect(liability.dig(:federal, :credits)).to eq(500.0)
    expect(liability.dig(:federal, :projected_refund_or_owed))
      .to eq((57_000.0 - (liability.dig(:federal, :total) - 500.0)).round(2))

    expect(liability.dig(:state, :withheld_and_paid)).to eq(23_000.0)
    expect(liability[:total_liability])
      .to eq((liability.dig(:federal, :total) - 500.0 + liability.dig(:state, :total)).round(2))

    headroom = liability[:bracket_headroom]
    expect(headroom.dig(:to_next_federal_bracket, :current_rate)).to eq(0.35)
    expect(headroom.dig(:to_next_federal_bracket, :next_rate)).to eq(0.37)
    expect(headroom.dig(:to_next_federal_bracket, :amount)).to be > 0
    expect(headroom[:ltcg_zero_headroom]).to eq(0.0) # far above the 0% breakpoint

    expect(liability.dig(:assumptions, :figures_status, :federal)).to eq("final")
    expect(liability.dig(:assumptions, :notes).join).to include("qualified")
  end

  it "is null liability without a complete profile" do
    profile.update!(projected_wages: 0)
    expect(report[:liability]).to be_nil
  end

  it "uses the entered projected state tax for a state Fin doesn't model" do
    profile.update!(state: "NY", projected_state_tax: 18_000)
    liability = report[:liability]

    expect(liability[:state]).to include(
      regular_tax: 18_000.0, amt: 0.0, total: 18_000.0, taxable_income: nil, marginal_ordinary_rate: nil,
      withheld_and_paid: 23_000.0, projected_refund_or_owed: 5_000.0
    )
    expect(liability[:total_liability]).to eq((liability.dig(:federal, :total) - 500.0 + 18_000.0).round(2))
    expect(liability.dig(:assumptions, :figures_status, :state)).to be_nil
    expect(liability.dig(:assumptions, :notes).join).to include("New York tax is the projected amount entered")

    payments = report[:payments]
    expect(payments.dig(:safe_harbor, :state)).to include(status: "unknown")
    expect(payments[:due_dates].select { |d| d[:jurisdiction] == "state" }.map { |d| d[:weight] })
      .to eq([ 0.25, 0.25, 0.25, 0.25 ])
  end

  it "lets an entered projected state tax override the California estimate" do
    profile.update!(projected_state_tax: 12_345)

    expect(report.dig(:liability, :state)).to include(total: 12_345.0, marginal_ordinary_rate: nil)
    # The CA safe harbor and 30/40/0/30 schedule still apply to a California resident.
    expect(report.dig(:payments, :safe_harbor, :state)).to include(status: "uncovered", required_annual: 44_000.0)
    expect(report.dig(:payments, :due_dates).select { |d| d[:jurisdiction] == "state" }.map { |d| d[:weight] })
      .to eq([ 0.30, 0.40, 0.0, 0.30 ])
  end

  it "zeroes state tax for a state without an income tax and drops its safe harbor and due dates" do
    profile.update!(state: "TX")

    expect(report.dig(:liability, :state)).to include(total: 0.0, amt: 0.0)
    expect(report.dig(:liability, :assumptions, :notes).join).to include("Texas has no state income tax")
    expect(report.dig(:payments, :safe_harbor, :state)).to include(status: "not_applicable")
    expect(report.dig(:payments, :due_dates).map { |d| d[:jurisdiction] }.uniq).to eq([ "federal" ])
  end

  it "reports payments, derived quarters, due-date windows, and safe harbor against withholding + payments" do
    payments = report[:payments]
    expect(payments[:kind]).to eq("record")

    expect(payments.dig(:federal, :withholding)).to eq(50_000.0)
    expect(payments.dig(:federal, :total)).to eq(55_000.0)
    expect(payments.dig(:federal, :estimated).sole).to include(amount: 5_000.0, quarter: "Q1")
    expect(payments.dig(:state, :estimated).sole).to include(amount: 3_000.0, quarter: "Q2")

    due = payments[:due_dates]
    expect(due.length).to eq(8)
    federal_q1 = due.find { |d| d[:jurisdiction] == "federal" && d[:label] == "Q1" }
    expect(federal_q1).to include(date: "#{year}-04-15", paid_in_window: 5_000.0, weight: 0.25)
    state_weights = due.select { |d| d[:jurisdiction] == "state" }.map { |d| d[:weight] }
    expect(state_weights).to eq([ 0.30, 0.40, 0.0, 0.30 ])
    state_q3 = due.find { |d| d[:jurisdiction] == "state" && d[:label] == "Q3" }
    expect(state_q3[:paid_in_window]).to eq(0.0)
    q4 = due.find { |d| d[:jurisdiction] == "federal" && d[:label] == "Q4" }
    expect(q4[:date]).to eq("#{year + 1}-01-15")

    harbor = payments[:safe_harbor]
    # Prior AGI 200k > 150k → 110% × 40,000 = 44,000 required.
    expect(harbor[:federal]).to include(status: "covered", required_annual: 44_000.0, paid: 57_000.0)
    expect(harbor[:state]).to include(status: "uncovered", required_annual: 44_000.0, paid: 23_000.0)
    expect(harbor[:state][:installment_weights]).to eq([ 0.30, 0.40, 0.0, 0.30 ])
  end

  it "resolves transfer legs in batched queries that don't scale per transfer" do
    # More transfers than there are leg classes: the old per-row
    # #to_transaction/#from_transaction resolution issued 1-2 queries per
    # transfer, so this count would grow with the loop below.
    5.times do |i|
      leg = create(:investment_transaction, account: t401k, transaction_type: tt_other,
                   security: nil, trade_date: Date.new(year, 6, 1 + i), amount_usd: 100)
      create(:transfer, :confirmed, amount: 100,
             to_transaction_id: leg.id, to_transaction_type: "InvestmentTransaction",
             counterparty_account_id: checking.id)
    end

    service = described_class.new(household: household, year: year)
    leg_queries = count_queries { service.send(:transfer_contributions_by_account) }
                    .grep(/FROM "(cash_transactions|investment_transactions)"/)
    # One batched load per leg class (cash + investment), regardless of
    # transfer count.
    expect(leg_queries.size).to be <= 2
  end

  it "tracks contributions per bucket from transfers into tagged accounts plus adjustments" do
    buckets = report[:contributions][:buckets].index_by { |b| b[:key] }

    bucket_401k = buckets["401k"]
    # 10,000 pair transfer + 5,000 one-sided external + 1,000 adjustment; the
    # prior-year 7,000 transfer must not count.
    expect(bucket_401k[:transfers_total]).to eq(15_000.0)
    expect(bucket_401k[:adjustments_total]).to eq(1_000.0)
    expect(bucket_401k[:contributed]).to eq(16_000.0)
    expect(bucket_401k[:limit]).to eq(24_500.0)
    expect(bucket_401k[:accounts].map { |a| a[:name] }).to contain_exactly("Linked 401k", "External 401k")

    expect(buckets["ira"]).to include(contributed: 0.0, limit: 7_500.0)
    expect(buckets["hsa"][:limit]).to eq(4_400.0) # single filing status
    expect(buckets["education"][:informational]).to be(true)
  end

  it "flags household-wide wash sales with the permanent-disallowance marker" do
    findings = report[:flags][:wash_sales]
    expect(findings.sole).to include(
      security_label: "CCC",
      sale_date:      Date.new(year, 5, 1),
      sale_account:   "Brokerage",
      loss:           -400.0,
      purchase_date:  Date.new(year, 5, 10),
      purchase_account: "IRA",
      permanent:      true
    )
  end

  it "lists checklist items in documents and stays inside the household" do
    expect(report[:documents][:items].map { |i| i[:kind] }).to include(TaxChecklistItem::Kind::CharitableReceipt)

    other = create(:household)
    empty_report = Current.set(household: other) { described_class.build(household: other, year: year) }
    expect(empty_report[:income][:interest]).to eq(0.0)
    expect(empty_report[:income][:dividends]).to eq(0.0)
    expect(empty_report[:liability]).to be_nil
    expect(empty_report[:contributions][:buckets].sum { |b| b[:contributed] }).to eq(0.0)
    expect(empty_report[:flags][:wash_sales]).to be_empty
    expect(empty_report[:documents][:items]).to be_empty
  end
end
