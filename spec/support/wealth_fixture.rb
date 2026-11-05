# One household's worth of populated wealth data — brokerage, crypto, cash
# spend, subscriptions, budget, loan + property, equity grants, tax year and
# stats — for the swagger specs. The OpenAPI document is validated against
# live responses, and an empty array never exercises its item schema, so
# every list these endpoints return needs at least one row.
module WealthFixture
  Fixture = Struct.new(
    :brokerage, :ira, :checking, :card, :crypto_account,
    :aapl, :vti, :btc, :spy,
    :groceries, :dining, :produce, :charity, :merchant,
    :series, :loan, :property, :company, :iso_grant, :rsu_grant, :exercise,
    keyword_init: true
  )

  def build_wealth_fixture
    today   = Date.current
    year    = today.year
    purchase_type = TransactionType.find_by(code: "100") || create(:transaction_type, :purchase)
    sale_type     = TransactionType.find_by(code: "200") || create(:transaction_type, :sale)
    dividend_type = TransactionType.find_by(code: "011") || create(:transaction_type, :dividend)

    broker    = create(:broker, name: "Fidelity")
    brokerage = create(:account, broker: broker, name: "Brokerage", account_type: "Invt Mgmt")
    ira       = create(:account, broker: broker, name: "Roth IRA", account_type: "IRA", tax_treatment: "roth_ira")
    checking  = create(:account, broker: broker, name: "Checking", account_type: "Checking")
    card      = create(:account, broker: broker, name: "Sapphire", account_type: "Credit Card")
    crypto_account = create(:account, broker: broker, name: "Coinbase", account_type: "Crypto")

    aapl = create(:security, ticker: "AAPL", name: "Apple Inc.", security_type: "Common Stock", instrument_class: "equity",
                             instrument_attributes: { "sector" => "Technology", "industry" => "Consumer Electronics" })
    vti  = create(:security, ticker: "VTI", name: "Vanguard Total Market ETF", security_type: "ETF", instrument_class: "etf")
    btc  = create(:security, :without_cusip, ticker: "BTC", name: "Bitcoin", security_type: ::Security::CRYPTO_TYPE, instrument_class: "crypto")
    spy  = create(:security, ticker: "SPY", name: "SPDR S&P 500", security_type: "ETF", instrument_class: "etf")
    SecurityWatch.find_or_create_by!(household: Current.household, security: vti)
    create(:security_label, security: aapl, label: "Core")

    # A year and a half of daily candles with drift, so charts, movers, YTD
    # change and sparklines all have real values.
    { aapl => 150.0, vti => 220.0, btc => 40_000.0, spy => 450.0 }.each do |security, start|
      rows = [ 1, *(0..540).step(3) ].uniq.map do |i|
        close = (start * (1 + (540 - i) / 1500.0) * (1 + ((i % 7) - 3) / 200.0)).round(2)
        { security_id: security.id, date: today - i.days, granularity: Candle::GRANULARITY_DAILY, open: close * 0.99,
          high: close * 1.01, low: close * 0.98, close: close, adjusted_close: close, volume: 1_000_000,
          currency: "USD", source: "alpha_vantage" }
      end
      Candle.insert_all!(rows)
    end
    create(:instrument_quote, security: btc, price: 62_000)
    create(:corporate_action, security: aapl, ex_date: today - 40.days)
    create(:corporate_action, :split, security: aapl, ex_date: today - 400.days)
    create(:security_news_article, security: aapl)
    SecurityOverview.create!(security: aapl, sector: "Technology", industry: "Consumer Electronics", exchange: "NASDAQ",
                             country: "USA", currency: "USD", description: "Designs consumer electronics.", market_cap: 3_000_000_000_000,
                             pe_ratio: 30.1, forward_pe: 27.4, eps: 6.4, beta: 1.2, dividend_yield: 0.005, dividend_per_share: 0.96,
                             week_52_high: 240, week_52_low: 160, analyst_target_price: 250, profit_margin: 0.25,
                             return_on_equity: 1.5, revenue_ttm: 390_000_000_000, shares_outstanding: 15_000_000_000,
                             ex_dividend_date: today - 40.days, fetched_at: 1.day.ago)

    # Positions: current snapshots plus an older one for change-over-time.
    [ today, today - 35.days ].each do |as_of|
      create(:position_snapshot, account: brokerage, security: aapl, as_of_date: as_of, quantity: 20, price: 200, market_value: 4_000, cost_basis: 3_000, asset_class: "Domestic Equity")
      create(:position_snapshot, account: ira,       security: vti,  as_of_date: as_of, quantity: 30, price: 290, market_value: 8_700, cost_basis: 7_000, asset_class: "Domestic Equity")
      create(:position_snapshot, account: crypto_account, security: btc, as_of_date: as_of, quantity: 0.5, price: 62_000, market_value: 31_000, cost_basis: 20_000, asset_class: "Crypto")
    end

    # Ledger: buys across accounts, a realized sale with gain, dividends.
    create(:investment_transaction, account: brokerage, security: aapl, transaction_type: purchase_type, trade_date: today - 300.days, quantity: 25, price_usd: 120, amount_usd: -3_000, cost_usd: 3_000, description: "BOUGHT AAPL")
    create(:investment_transaction, account: brokerage, security: aapl, transaction_type: sale_type, trade_date: today - 20.days, quantity: -5, price_usd: 210, amount_usd: 1_050, gl_short_usd: 0, gl_long_usd: 450, description: "SOLD AAPL")
    create(:investment_transaction, account: brokerage, security: aapl, transaction_type: dividend_type, trade_date: today - 30.days, quantity: nil, price_usd: nil, amount_usd: 12.5, income_usd: 12.5, description: "DIVIDEND AAPL")
    create(:investment_transaction, account: ira, security: vti, transaction_type: purchase_type, trade_date: today - 90.days, quantity: 30, price_usd: 233, amount_usd: -7_000, cost_usd: 7_000, description: "BOUGHT VTI")
    create(:investment_transaction, account: crypto_account, security: btc, transaction_type: purchase_type, trade_date: today - 60.days, quantity: 0.5, price_usd: 40_000, amount_usd: -20_000, cost_usd: 20_000, description: "BOUGHT BTC")
    create(:investment_lot, account: brokerage, security: aapl, acquired_date: today - 300.days, quantity: 20, cost_basis: 3_000)

    # Balances for the cash side of net worth.
    AccountBalanceSnapshot.create!(account: crypto_account, balance: 31_000, balance_usd: 31_000, recorded_at: today - 10.days, source: "manual")
    [ checking, card ].each_with_index do |account, i|
      [ today - 60.days, today ].each do |recorded|
        AccountBalanceSnapshot.create!(account: account, balance: i.zero? ? 12_000 : -1_500, balance_usd: i.zero? ? 12_000 : -1_500,
                                       recorded_at: recorded, source: "manual")
      end
    end

    # Cash spend: categories (with a subcategory and a charitable one),
    # card charges every month, payroll into checking, a return.
    groceries = create(:category, name: "Groceries", budget_kind: "flex")
    produce   = create(:category, name: "Produce", parent: groceries, budget_kind: "flex")
    dining    = create(:category, name: "Dining", budget_kind: "flex")
    rent_cat  = create(:category, name: "Housing", budget_kind: "fixed")
    gifts     = create(:category, name: "Gifts", budget_kind: "non_monthly")
    charity   = create(:category, name: "Charity", charitable: true)
    bakery    = create(:category, name: "Bakery", parent: groceries, budget_kind: "flex")
    merchant  = create(:merchant, name: "Whole Foods", category: groceries)
    netflix   = create(:merchant, name: "Netflix", category: dining)
    tag       = create(:tag, name: "Vacation")
    14.times do |m|
      month = (today << m).beginning_of_month
      create(:cash_transaction, :credit_card, :sale, account: card, amount: -(180 + m * 7), category: groceries, merchant: merchant,
                                                     transaction_date: month + 3, description: "WHOLE FOODS")
      create(:cash_transaction, :credit_card, :sale, account: card, amount: -64, category: produce, merchant: merchant,
                                                     transaction_date: month + 8, description: "WHOLE FOODS PRODUCE")
      create(:cash_transaction, :credit_card, :sale, account: card, amount: -15.99, category: dining, merchant: netflix,
                                                     transaction_date: month + 14, description: "NETFLIX.COM")
      create(:cash_transaction, :bank, :debit, account: checking, amount: -2_400, category: rent_cat, transaction_date: month + 1, description: "RENT")
      create(:cash_transaction, :bank, :credit, account: checking, amount: 6_500, transaction_date: month + 14, description: "PAYROLL ACME")
    end
    create(:cash_transaction, :credit_card, :sale, account: card, amount: -900, category: gifts, transaction_date: today.beginning_of_month + 1, description: "BIRTHDAY GIFT")
    create(:cash_transaction, :credit_card, :sale, account: card, amount: -18, category: bakery, merchant: merchant,
                                                   transaction_date: today.beginning_of_month + 2, description: "WHOLE FOODS BAKERY")
    create(:cash_transaction, :credit_card, :return, account: card, amount: 25, category: groceries, merchant: merchant, transaction_date: today.beginning_of_month + 2)
    create(:cash_transaction, :bank, :debit, account: checking, amount: -500, category: charity, transaction_date: Date.new(year, 2, 10), description: "RED CROSS")
    tagged = create(:cash_transaction, :credit_card, :sale, account: card, amount: -3_200, category: dining, transaction_date: today.beginning_of_month + 4, description: "RESORT")
    CashTransactionTag.create!(cash_transaction: tagged, tag: tag)

    # A confirmed contribution into the IRA, for the tax contributions bucket.
    out_leg = create(:cash_transaction, :bank, :transfer, account: checking, amount: -1_000, transaction_date: Date.new(year, 3, 1), description: "TRANSFER TO IRA")
    in_leg  = create(:investment_transaction, account: ira, security: nil, transaction_type: create(:transaction_type, category: "Transfer In"),
                                              trade_date: Date.new(year, 3, 1), quantity: nil, price_usd: nil, amount_usd: 1_000, description: "CONTRIBUTION")
    create(:transfer, :confirmed, amount: 1_000, from_transaction_type: "CashTransaction", from_transaction_id: out_leg.id,
                                             to_transaction_type: "InvestmentTransaction", to_transaction_id: in_leg.id)

    # Subscription with paid history and an upcoming charge.
    series = create(:recurring_series, :active, name: "Netflix", merchant: netflix, account: card)
    paid_txn = CashTransaction.where(merchant: netflix).order(transaction_date: :desc).first
    create(:recurring_occurrence, :paid, recurring_series: series, cash_transaction: paid_txn)
    create(:recurring_occurrence, recurring_series: series, expected_date: today + 5)

    # Budget: a standing plan set last month and carried forward, with a
    # subcategory line, a yearly line, a one-month override this month, and
    # an everything-else amount.
    month_start = today.beginning_of_month
    [ [ groceries, 400 ], [ produce, 80 ], [ rent_cat, 2_400 ], [ dining, 150 ] ].each do |category, planned|
      BudgetLine.create!(category: category, month: month_start.prev_month, planned: planned)
    end
    BudgetLine.create!(category: gifts, month: month_start.prev_month, planned: 1_200, period: "yearly")
    BudgetLine.create!(category: dining, month: month_start, planned: 200, mode: "month_only")
    BudgetPeriod.create!(month: month_start.prev_month, income_planned: 6_500, other_planned: 300)

    # Property with a mortgage and payments linked to it.
    property = create(:real_estate_property, name: "Home", purchase_date: today - 3.years, purchase_price: 500_000,
                                             property_type: "Single Family", bedrooms: 3, bathrooms: 2, square_footage: 1_800,
                                             year_built: 1995, notes: "Primary residence", last_synced_at: 2.days.ago)
    create(:real_estate_valuation, real_estate_property: property, as_of: today - 30.days, amount: 640_000, value_low: 600_000, value_high: 680_000)
    create(:real_estate_valuation, real_estate_property: property, as_of: today - 400.days, amount: 610_000, source: "manual")
    create(:real_estate_valuation, real_estate_property: property, as_of: today - 200.days, amount: 450_000, source: "tax_assessment")
    create(:rentcast_configuration)
    loan = create(:loan, name: "Mortgage", lender: "Big Bank", merchant: create(:merchant, name: "Big Bank Mortgage"), account: checking,
                         real_estate_property: property, monthly_payment: 2_100, escrow_property_tax: 250, escrow_insurance: 100,
                         start_date: today - 3.years, original_principal: 400_000, balance_anchor_amount: 380_000,
                         balance_anchor_date: today - 1.year, notes: "30-year fixed")
    3.times do |m|
      create(:cash_transaction, :bank, :debit, account: checking, amount: -2_100, loan: loan, transaction_date: (today << m).beginning_of_month + 5, description: "BIG BANK MORTGAGE")
    end
    create(:cash_transaction, :bank, :debit, account: checking, amount: -2_100, transaction_date: today - 2.days, description: "BIG BANK MORTGAGE PMT")
    create(:loan, name: "Car loan", loan_type: "auto", lender: "Credit Union", original_principal: 30_000, interest_rate: 4.5,
                  term_months: 60, start_date: today - 18.months, monthly_payment: 560)

    # Equity: a private company with a 409A, an ISO grant with an exercise
    # and a sale, and a public RSU grant.
    company = create(:equity_company, name: "Acme Corp", preferred_price: 25, notes: "Series C", qsbs_candidate: true)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 12, effective_date: today - 60.days)
    iso_grant = create(:equity_grant, equity_company: company, label: "2024 ISO", grant_date: today - 2.years, expiration_date: today + 8.years,
                                      notes: "Early exercise allowed")
    exercise = create(:equity_grant_event, equity_grant: iso_grant, kind: "exercise", occurred_on: Date.new(year, 1, 15), quantity: 500,
                                           share_price: 12, notes: "Exercised")
    create(:equity_grant_event, equity_grant: iso_grant, kind: "sale", occurred_on: Date.new(year, 2, 15), quantity: 100, share_price: 14)
    public_co = create(:equity_company, name: "Apple", public_company: true, security: aapl)
    rsu_grant = create(:equity_grant, :rsu, equity_company: public_co, grant_date: today - 1.year, quantity: 400)

    # Tax year: profile, one of each adjustment kind, payments, checklist.
    create(:tax_profile, tax_year: year, prior_year_total_tax: 60_000, prior_year_agi: 380_000, projected_state_tax: 25_000)
    create(:tax_adjustment, tax_year: year, kind: "income", label: "Consulting", amount: 5_000, notes: "1099-NEC")
    create(:tax_adjustment, tax_year: year, kind: "deduction", label: "Mortgage interest", amount: 12_000)
    create(:tax_adjustment, tax_year: year, kind: "credit", label: "Child tax credit", amount: 2_000)
    create(:tax_adjustment, tax_year: year, kind: "contribution", bucket: "hsa", label: "HSA payroll", amount: 3_000)
    create(:estimated_tax_payment, tax_year: year, jurisdiction: "federal", paid_on: Date.new(year, 4, 10), amount: 5_000, notes: "Q1")
    create(:estimated_tax_payment, tax_year: year, jurisdiction: "state", paid_on: Date.new(year, 4, 10), amount: 1_500)
    create(:tax_checklist_item, tax_year: year, kind: "1099_consolidated", source_label: "Fidelity", notes: "Arrives mid-February")

    # A wash sale: AAPL sold at a loss and rebought within 30 days.
    create(:investment_transaction, account: brokerage, security: aapl, transaction_type: sale_type, trade_date: Date.new(year, 5, 1), quantity: -2, price_usd: 100, amount_usd: 200, gl_short_usd: -150, description: "SOLD AAPL LOSS")
    create(:investment_transaction, account: brokerage, security: aapl, transaction_type: purchase_type, trade_date: Date.new(year, 5, 10), quantity: 2, price_usd: 105, amount_usd: -210, cost_usd: 210, description: "BOUGHT AAPL")

    # Stats: a year of stored metric points so sparklines and paces fill in.
    13.times do |m|
      create(:metric_point, metric_key: "monthly_spend", date: (today << m).beginning_of_month, value: 3_000 + m * 40)
    end

    SavedReport.create!(name: "Groceries YTD",
                        config: { section: "spending", preset: "ytd", tag_id: tag.id, exclude_tag_ids: [], hash: "#spending" }.to_json)

    Fixture.new(brokerage: brokerage, ira: ira, checking: checking, card: card, crypto_account: crypto_account,
                aapl: aapl, vti: vti, btc: btc, spy: spy, groceries: groceries, dining: dining, produce: produce,
                charity: charity, merchant: merchant, series: series, loan: loan, property: property, company: company,
                iso_grant: iso_grant, rsu_grant: rsu_grant, exercise: exercise)
  end
end
