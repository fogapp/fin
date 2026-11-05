require "rails_helper"

RSpec.describe Valuation::PortfolioSeries do
  let(:account)  { create(:account) }
  let(:security) { create(:security, ticker: "VTI", instrument_class: "etf") }
  let(:purchase_type) { create(:transaction_type, :purchase) }
  let(:sale_type)     { create(:transaction_type, :sale) }

  def candle!(date, close, sec: security)
    Candle.create!(security: sec, date: date, close: close, adjusted_close: close,
                   currency: "USD", source: "alpha_vantage")
  end

  it "values ledger quantities with adjusted closes, carrying prices forward" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 10, cost_usd: 1000,
           trade_date: Date.new(2026, 6, 1))
    create(:investment_transaction, account: account, security: security,
           transaction_type: sale_type, quantity: -4, cost_usd: 400,
           trade_date: Date.new(2026, 6, 10))
    candle!(Date.new(2026, 6, 1), 100)
    candle!(Date.new(2026, 6, 10), 110)
    # no candle on the 11th — price carries forward

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 11))

    expect(series["2026-06-01"]).to eq(1000.0)  # 10 × 100
    expect(series["2026-06-05"]).to eq(1000.0)  # price carried
    expect(series["2026-06-10"]).to eq(660.0)   # 6 × 110
    expect(series["2026-06-11"]).to eq(660.0)
  end

  it "starts each holding at its first acquisition, not the window start" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 5, cost_usd: 500,
           trade_date: Date.new(2026, 6, 15))
    candle!(Date.new(2026, 6, 15), 100)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 16))
    expect(series).not_to have_key("2026-06-14")
    expect(series["2026-06-15"]).to eq(500.0)
  end

  it "seeds pre-window quantity and price when the window starts after the first trade" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 10, cost_usd: 1000,
           trade_date: Date.new(2026, 6, 1))
    candle!(Date.new(2026, 6, 1), 100)
    # no trades and no closes inside the window — both must carry in

    series = described_class.call(from: Date.new(2026, 6, 5), to: Date.new(2026, 6, 7))

    expect(series["2026-06-05"]).to eq(1000.0) # 10 × the 6/1 close
    expect(series["2026-06-07"]).to eq(1000.0)
    expect(series).not_to have_key("2026-06-01") # nothing emitted pre-window
  end

  it "carries observation-only positions flat when no ledger exists" do
    obs_sec = create(:security, ticker: "OBS1")
    create(:position_snapshot, account: account, security: obs_sec,
           as_of_date: Date.new(2026, 6, 5), quantity: 3,
           source_row_hash: "csv-obs")
    candle!(Date.new(2026, 6, 5), 50, sec: obs_sec)

    series = described_class.call(from: Date.new(2026, 6, 5), to: Date.new(2026, 6, 7))
    expect(series["2026-06-05"]).to eq(150.0)
    expect(series["2026-06-07"]).to eq(150.0)
  end

  it "never values a net-negative ledger as a negative holding" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: sale_type, quantity: -5, cost_usd: 500,
           trade_date: Date.new(2026, 6, 1))
    candle!(Date.new(2026, 6, 1), 100)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 2))
    expect(series).to eq({})
  end

  it "sums the same instrument held in two accounts" do
    other_account = create(:account)
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 10, cost_usd: 1000,
           trade_date: Date.new(2026, 6, 1))
    create(:investment_transaction, account: other_account, security: security,
           transaction_type: purchase_type, quantity: 5, cost_usd: 500,
           trade_date: Date.new(2026, 6, 1))
    candle!(Date.new(2026, 6, 1), 100)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 1))
    expect(series["2026-06-01"]).to eq(1500.0) # (10 + 5) × 100
  end

  # Both stores cover the same date; the candle is authoritative. Batching the
  # price lookups has to preserve that precedence, so this pins it.
  it "prefers a candle over a legacy market_price on the same date" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 2, cost_usd: 200,
           trade_date: Date.new(2026, 6, 1))
    create(:market_price, security: security, date: Date.new(2026, 6, 1), close: 999)
    candle!(Date.new(2026, 6, 1), 100)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 1))
    expect(series["2026-06-01"]).to eq(200.0) # 2 × 100, not 2 × 999
  end

  it "falls back to legacy market_prices when no candle exists" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 2, cost_usd: 200,
           trade_date: Date.new(2026, 6, 1))
    # adjusted_close, not close: COALESCE(adjusted_close, close) means the
    # adjusted column wins whenever it is populated, which the factory does.
    create(:market_price, security: security, date: Date.new(2026, 6, 1),
           close: 50, adjusted_close: 50)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 1))
    expect(series["2026-06-01"]).to eq(100.0) # 2 × 50
  end

  # Resolution used to cost a Security lookup, a grouped ledger sum and two
  # price queries per (account, instrument) — ~2,000 queries and 2.8s on the
  # production portfolio. It is now a fixed handful regardless of breadth.
  it "does not scale its query count with the number of holdings" do
    5.times do |i|
      sec = create(:security, ticker: "BULK#{i}")
      create(:investment_transaction, account: account, security: sec,
             transaction_type: purchase_type, quantity: 1, cost_usd: 100,
             trade_date: Date.new(2026, 6, 1))
      candle!(Date.new(2026, 6, 1), 100, sec: sec)
    end

    expect { described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 2)) }
      .to issue_at_most(16).queries # + confirmed conversions and share splits, one query each
  end

  it "sums across instruments per day" do
    other = create(:security, ticker: "AAPL", instrument_class: "equity")
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 1, cost_usd: 100,
           trade_date: Date.new(2026, 6, 1))
    create(:investment_transaction, account: account, security: other,
           transaction_type: purchase_type, quantity: 2, cost_usd: 200,
           trade_date: Date.new(2026, 6, 1))
    candle!(Date.new(2026, 6, 1), 100)
    candle!(Date.new(2026, 6, 1), 200, sec: other)

    series = described_class.call(from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 1))
    expect(series["2026-06-01"]).to eq(500.0) # 1×100 + 2×200
  end

  describe ".call_by_account" do
    let(:from) { Date.new(2026, 6, 1) }
    let(:to)   { Date.new(2026, 6, 5) }

    def snapshot!(qty:, price: 100, market_value: nil, as_of: to, acct: account, sec: security)
      create(:position_snapshot, account: acct, security: sec, as_of_date: as_of,
             quantity: qty, price: price, market_value: market_value || (qty * price))
    end

    def buy!(qty, date, acct: account, sec: security)
      create(:investment_transaction, account: acct, security: sec, transaction_type: purchase_type,
             quantity: qty, cost_usd: qty * 100, trade_date: date)
    end

    it "matches the plain ledger walk when the ledger agrees with the snapshot" do
      buy!(10, Date.new(2026, 6, 3))
      snapshot!(qty: 10)
      candle!(Date.new(2026, 6, 3), 100)

      series = described_class.call_by_account(from: from, to: to)[account.id]

      expect(series[Date.new(2026, 6, 3)]).to eq(1000.0)
      expect(series[Date.new(2026, 6, 5)]).to eq(1000.0)
      expect(series).not_to have_key(Date.new(2026, 6, 2))
    end

    it "carries shares the ledger never saw back from the snapshot" do
      # 6 shares transferred in before the ledger begins; ledger only has the 4-share buy
      buy!(4, Date.new(2026, 6, 3))
      snapshot!(qty: 10)
      candle!(Date.new(2026, 5, 29), 100)

      series = described_class.call_by_account(from: from, to: to)[account.id]

      expect(series[Date.new(2026, 6, 1)]).to eq(600.0)  # 6 × 100, seeded from the pre-window close
      expect(series[Date.new(2026, 6, 3)]).to eq(1000.0) # 10 × 100
    end

    it "falls back to the snapshot price when no closes exist" do
      snapshot!(qty: 3, price: 50)

      series = described_class.call_by_account(from: from, to: to)[account.id]

      expect(series[from]).to eq(150.0)
      expect(series[to]).to eq(150.0)
    end

    it "keeps a reported position at its last close however old, not today's snapshot price" do
      # A muni the custodian last priced in June: August is valued at June's
      # close, not at the September snapshot price the engine can see.
      bond = create(:security, ticker: nil, name: "CA GO 5% 2032", instrument_class: "bond")
      snapshot!(qty: 10_000, price: 99.0, market_value: 9_900, as_of: Date.new(2026, 9, 25), sec: bond)
      candle!(Date.new(2026, 6, 28), 104.0, sec: bond)

      aug = Date.new(2026, 8, 20)
      values = [ Date.new(2026, 8, 20), Date.new(2026, 7, 1), Date.new(2025, 9, 25) ].map do |window_from|
        described_class.call_by_account(from: window_from, to: Date.new(2026, 9, 25))[account.id][aug]
      end

      expect(values).to all(eq(10_400.0)) # 10,000 face × 104 / 100, whatever the window
    end

    it "scales per-100-of-face bonds back to dollars" do
      bond = create(:security, ticker: nil, name: "UST 4% 2030", instrument_class: "bond")
      snapshot!(qty: 10_000, price: 98.5, market_value: 9_850, sec: bond)

      series = described_class.call_by_account(from: from, to: to)[account.id]

      expect(series[to]).to eq(9_850.0)
    end

    it "scales a bond's per-100 closes exactly once, reported or sold" do
      held_bond = create(:security, ticker: nil, name: "Muni 5% 2032", instrument_class: "bond")
      snapshot!(qty: 50_000, price: 108, market_value: 54_000, sec: held_bond)
      Candle.create!(security: held_bond, date: to, close: 110, currency: "USD", source: "custodian")

      sold_bond = create(:security, ticker: nil, name: "Muni 4% 2027", instrument_class: "bond",
                                    instrument_attributes: { Security::QUOTE_BASIS_KEY => Security::QUOTE_BASIS_PER_HUNDRED })
      buy!(25_000, Date.new(2026, 6, 1), sec: sold_bond, acct: create(:account))
      Candle.create!(security: sold_bond, date: to, close: 101, currency: "USD", source: "custodian")

      total = described_class.call(from: to, to: to)[to.to_s]

      expect(total).to eq(55_000.0 + 25_250.0) # 50,000 × 1.10 + 25,000 × 1.01
    end

    it "values a sold-out instrument off the ledger and zeros the account after the sale" do
      buy!(5, Date.new(2026, 6, 2))
      create(:investment_transaction, account: account, security: security, transaction_type: sale_type,
             quantity: -5, cost_usd: 500, trade_date: Date.new(2026, 6, 4))
      candle!(Date.new(2026, 6, 2), 100)

      series = described_class.call_by_account(from: from, to: to)[account.id]

      expect(series[Date.new(2026, 6, 3)]).to eq(500.0)
      expect(series[Date.new(2026, 6, 4)]).to eq(0.0)
      expect(series[Date.new(2026, 6, 5)]).to eq(0.0)
    end

    it "does not double-count a holding whose ledger and snapshot sit on different accounts" do
      custodian = create(:account)
      buy!(10, Date.new(2026, 6, 1))
      snapshot!(qty: 10, acct: custodian)
      candle!(Date.new(2026, 6, 1), 100)

      by_account = described_class.call_by_account(from: from, to: to)

      expect(by_account.keys).to eq([ custodian.id ])
      expect(by_account[custodian.id][to]).to eq(1000.0)
    end

    it "narrows to the requested accounts" do
      other = create(:account)
      snapshot!(qty: 1)
      snapshot!(qty: 2, acct: other)

      expect(described_class.call_by_account(from: from, to: to, account_ids: [ other.id ]).keys)
        .to eq([ other.id ])
    end

    # Production cases (Sept 2026 comparison against recorded balances).
    context "with a custodian-reported account" do
      let(:first_seen) { Date.new(2026, 6, 23) }
      let(:latest)     { Date.new(2026, 9, 25) }
      let(:held)       { create(:security, ticker: "TSM") }
      let(:adr)        { create(:security, ticker: "SMNEY") }

      before do
        # The custodian's first and latest reports on the account, neither
        # mentioning the ADR.
        snapshot!(qty: 10, as_of: first_seen, sec: held)
        snapshot!(qty: 10, as_of: latest, sec: held)
        candle!(first_seen - 1, 100, sec: held)
      end

      it "stops valuing a converted ADR when its closes stop, not at its last close forever" do
        # Bought, then converted on 2026-01-30 — the conversion never reached the ledger.
        buy!(582, Date.new(2025, 1, 30), sec: adr)
        candle!(Date.new(2026, 1, 29), 175.64, sec: adr)

        value = ->(date) { described_class.call_by_account(from: date, to: date)[account.id]&.fetch(date, 0.0) }

        # The reported holding (10 × its snapshot price) is 1,000 throughout.
        expect(value.(Date.new(2026, 1, 29))).to eq(102_222.48 + 1_000.0)
        expect(value.(Date.new(2026, 3, 15))).to eq(102_222.48 + 1_000.0) # within STALE_CLOSE_DAYS
        expect(value.(Date.new(2026, 3, 16))).to eq(1_000.0)              # stale: the ADR drops out
        expect(value.(Date.new(2026, 7, 21))).to eq(1_000.0)
      end

      it "closes out a ledger-only holding the custodian never reported, from its first report" do
        # Still quoted (so the stale-price rule can't help), but the custodian
        # has never listed it: the ledger is missing the sale.
        buy!(5, Date.new(2026, 5, 1), sec: adr)
        [ Date.new(2026, 6, 20), Date.new(2026, 6, 22), Date.new(2026, 6, 24) ].each { |d| candle!(d, 50, sec: adr) }

        series = described_class.call_by_account(from: Date.new(2026, 6, 21), to: Date.new(2026, 6, 24))[account.id]

        expect(series[Date.new(2026, 6, 22)]).to eq(250.0 + 1_000.0)
        expect(series[first_seen]).to eq(1_000.0)
        expect(series[Date.new(2026, 6, 24)]).to eq(1_000.0)
      end

      it "closes out a holding the day after the custodian last reported it" do
        buy!(5, Date.new(2026, 5, 1), sec: adr)
        snapshot!(qty: 5, as_of: Date.new(2026, 7, 1), sec: adr) # a report it stopped refreshing
        (Date.new(2026, 6, 28)..Date.new(2026, 7, 3)).each { |d| candle!(d, 50, sec: adr) }

        series = described_class.call_by_account(from: Date.new(2026, 6, 30), to: Date.new(2026, 7, 3))[account.id]

        expect(series[Date.new(2026, 7, 1)]).to eq(250.0 + 1_000.0)
        expect(series[Date.new(2026, 7, 2)]).to eq(1_000.0)
      end

      it "only zeroes at the latest report when the ledger traded while the custodian was watching" do
        buy!(5, Date.new(2026, 7, 10), sec: adr)
        (Date.new(2026, 9, 20)..latest).each { |d| candle!(d, 50, sec: adr) }
        (Date.new(2026, 9, 20)..latest).each { |d| candle!(d, 100, sec: held) }

        series = described_class.call_by_account(from: Date.new(2026, 9, 24), to: latest)[account.id]

        expect(series[Date.new(2026, 9, 24)]).to eq(250.0 + 1_000.0)
        expect(series[latest]).to eq(1_000.0)
      end

      it "leaves a manual account's ledger-only holdings alone" do
        manual = create(:account)
        buy!(5, Date.new(2026, 5, 1), sec: adr, acct: manual)
        (Date.new(2026, 9, 20)..latest).each { |d| candle!(d, 50, sec: adr) }

        expect(described_class.call_by_account(from: latest, to: latest)[manual.id][latest]).to eq(250.0)
      end

      it "anchors sells recorded without their buys, even when the window ends before the snapshot" do
        # Custodian reports 1,725; the ledger only has the 1,000-share sale.
        sold = create(:security, ticker: "SMERY")
        snapshot!(qty: 1725, price: 32, as_of: latest, sec: sold)
        create(:investment_transaction, account: account, security: sold, transaction_type: sale_type,
               quantity: -1000, cost_usd: 32_000, trade_date: Date.new(2026, 8, 1))
        candle!(Date.new(2026, 7, 20), 36, sec: sold)
        candle!(Date.new(2026, 7, 20), 100, sec: held)

        day = Date.new(2026, 7, 21)
        series = described_class.call_by_account(from: day, to: day)[account.id]

        expect(series[day]).to eq(2725 * 36 + 1_000.0) # 1,725 + the 1,000 sold later
      end

      it "values a date the same whatever window surrounds it" do
        buy!(582, Date.new(2025, 1, 30), sec: adr)
        candle!(Date.new(2026, 1, 29), 175.64, sec: adr)
        (Date.new(2026, 7, 1)..Date.new(2026, 7, 31)).each { |d| candle!(d, 100 + d.day, sec: held) }

        [ Date.new(2026, 3, 15), Date.new(2026, 3, 16), Date.new(2026, 7, 21) ].each do |day|
          values = [
            [ day, day ], [ day - 30, day ], [ day - 400, day ], [ day, day + 30 ], [ day - 400, latest ]
          ].map { |f, t| described_class.call_by_account(from: f, to: t)[account.id]&.fetch(day, 0.0) }

          expect(values.uniq.size).to eq(1), "#{day}: #{values.inspect}"
        end
      end

      describe "sales the ledger has no purchases for" do
        let(:harvested) { create(:security, ticker: "INTC") }

        before do
          (Date.new(2026, 4, 25)..latest).step(5).each { |d| candle!(d, 20, sec: harvested) }
          (Date.new(2026, 4, 25)..latest).step(5).each { |d| candle!(d, 100, sec: held) }
        end

        it "counts the sold shares as held until the sale, sold before the custodian's first report" do
          # Bought before the ledger began; only the tax-loss sale was recorded.
          create(:investment_transaction, account: account, security: harvested, transaction_type: sale_type,
                 quantity: -30, cost_usd: 600, trade_date: Date.new(2026, 5, 10))

          value = ->(date) { described_class.call_by_account(from: date, to: date)[account.id].fetch(date) }

          expect(value.(Date.new(2026, 5, 5))).to eq(30 * 20 + 1_000.0)
          expect(value.(Date.new(2026, 5, 10))).to eq(1_000.0)
          expect(value.(Date.new(2026, 7, 1))).to eq(1_000.0)
        end

        it "counts them while the custodian was watching too" do
          create(:investment_transaction, account: account, security: harvested, transaction_type: sale_type,
                 quantity: -50, cost_usd: 1000, trade_date: Date.new(2026, 8, 1))

          value = ->(date) { described_class.call_by_account(from: date, to: date)[account.id].fetch(date) }

          expect(value.(Date.new(2026, 7, 21))).to eq(50 * 20 + 1_000.0)
          expect(value.(Date.new(2026, 8, 5))).to eq(1_000.0)
        end

        it "records no synthetic flow — the sale is a ledger trade" do
          create(:investment_transaction, account: account, security: harvested, transaction_type: sale_type,
                 quantity: -30, cost_usd: 600, trade_date: Date.new(2026, 5, 10))

          expect(described_class.call_with_flows(from: Date.new(2026, 5, 1), to: Date.new(2026, 7, 1))[:flows]).to be_empty
        end
      end

      describe "a confirmed conversion" do
        let(:sponsored) { create(:security, ticker: "SMERY") }
        let(:converted_on) { Date.new(2026, 1, 30) }

        before do
          # 582 unsponsored ADRs converted 1:1 on 2026-01-30, then the
          # sponsored ADR split 5:1 — 2,910 of today's units, all reported.
          buy!(582, Date.new(2025, 1, 30), sec: adr)
          candle!(Date.new(2025, 12, 1), 170, sec: adr)
          candle!(Date.new(2026, 1, 29), 175.64, sec: adr)
          snapshot!(qty: 2910, price: 35, as_of: latest, sec: sponsored)
          candle!(converted_on, 35, sec: sponsored)
        end

        def convert!(status: SecurityConversion::Status::Confirmed, ratio: 5)
          SecurityConversion.create!(from_security: adr, to_security: sponsored, effective_date: converted_on,
                                     ratio: ratio, status: status)
        end

        let(:value) { ->(date) { described_class.call_by_account(from: date, to: date)[account.id].fetch(date) } }

        it "moves the shares on the conversion date instead of counting both before it" do
          convert!

          expect(value.(Date.new(2025, 12, 1))).to eq(582 * 170 + 1_000.0) # the old ADR only
          expect(value.(Date.new(2026, 1, 29))).to eq(582 * 175.64 + 1_000.0)
          expect(value.(Date.new(2026, 2, 2))).to eq(2910 * 35 + 1_000.0)  # the new ADR only
        end

        it "ignores a conversion that is only suggested" do
          convert!(status: SecurityConversion::Status::Suggested)

          # Unconfirmed, the reported ADR's unexplained shares carry back while
          # the old ADR is still held: the double count the record prevents.
          expect(value.(Date.new(2025, 12, 1))).to eq(582 * 170 + 2910 * 35 + 1_000.0)
        end

        it "leaves an account whose custodian still reports the old instrument after the date" do
          convert!
          snapshot!(qty: 582, price: 175, as_of: latest, sec: adr)

          expect(value.(Date.new(2026, 2, 2))).to be_within(0.01).of(582 * 175.64 + 2910 * 35 + 1_000.0)
        end

        it "produces no flow on the conversion day" do
          convert!

          flows = described_class.call_with_flows(from: Date.new(2026, 1, 1), to: Date.new(2026, 3, 1))[:flows]
          expect(flows).not_to have_key(converted_on)
        end

        it "values a date the same whatever window surrounds it" do
          convert!

          [ Date.new(2025, 12, 1), Date.new(2026, 2, 2) ].each do |day|
            values = [ [ day, day ], [ day - 90, day ], [ day - 400, latest ], [ day, day + 30 ] ]
              .map { |f, t| described_class.call_by_account(from: f, to: t)[account.id].fetch(day) }
            expect(values.uniq.size).to eq(1), "#{day}: #{values.inspect}"
          end
        end
      end

      describe ".call_with_flows" do
        it "records a custodian exit as an outflow of the value it removes" do
          buy!(5, Date.new(2026, 5, 1), sec: adr)
          [ Date.new(2026, 6, 20), Date.new(2026, 6, 22), Date.new(2026, 6, 24) ].each { |d| candle!(d, 50, sec: adr) }

          flows = described_class.call_with_flows(from: Date.new(2026, 6, 21), to: Date.new(2026, 6, 24))[:flows]

          expect(flows).to eq(first_seen => -250.0)
        end

        it "records a stale drop-out as an outflow, so the day's return is zero" do
          buy!(582, Date.new(2025, 1, 30), sec: adr)
          candle!(Date.new(2026, 1, 29), 175.64, sec: adr)

          result = described_class.call_with_flows(from: Date.new(2026, 3, 14), to: Date.new(2026, 3, 18))
          expect(result[:flows]).to eq(Date.new(2026, 3, 16) => -102_222.48)

          performance = Valuation::PortfolioPerformance.call(from: Date.new(2026, 3, 14), to: Date.new(2026, 3, 18))
          expect(performance[:twr_pct]).to eq(0.0)
        end

        it "records a holding's first price mid-window as an inflow" do
          manual = create(:account)
          buy!(10, Date.new(2026, 6, 1), sec: adr, acct: manual)
          candle!(Date.new(2026, 6, 10), 50, sec: adr)

          flows = described_class.call_with_flows(from: Date.new(2026, 6, 5), to: Date.new(2026, 6, 12),
                                                  account_ids: [ manual.id ])[:flows]
          expect(flows).to eq(Date.new(2026, 6, 10) => 500.0)
        end
      end
    end

    describe "share splits" do
      it "converts pre-split ledger quantities to today's units, ignoring spin-off adjustments" do
        buy!(10, Date.new(2026, 5, 1))
        CorporateAction.create!(security: security, kind: "split", ratio: 4, ex_date: Date.new(2026, 6, 3), source: "tiingo")
        CorporateAction.create!(security: security, kind: "split", ratio: 1.061, ex_date: Date.new(2026, 6, 4), source: "tiingo")
        snapshot!(qty: 40, price: 25)
        candle!(Date.new(2026, 5, 29), 25) # adjusted: already in post-split units

        series = described_class.call_by_account(from: from, to: to)[account.id]

        expect(series[from]).to eq(1000.0) # 40 × 25 before the split, not 10 × 25
        expect(series[to]).to eq(1000.0)
      end

      it "values a date the same whatever window surrounds it" do
        buy!(10, Date.new(2026, 5, 1))
        CorporateAction.create!(security: security, kind: "split", ratio: 4, ex_date: Date.new(2026, 6, 3), source: "tiingo")
        candle!(Date.new(2026, 5, 29), 25)

        day = Date.new(2026, 6, 2)
        values = [ [ day, day ], [ day - 30, day ], [ day, to ] ]
          .map { |f, t| described_class.call_by_account(from: f, to: t)[account.id].fetch(day) }
        expect(values).to all(eq(1000.0))
      end
    end

    it "is what .call sums, per day" do
      other = create(:account)
      buy!(10, Date.new(2026, 6, 1))
      snapshot!(qty: 3, price: 50, acct: other, sec: create(:security))
      candle!(Date.new(2026, 6, 1), 100)

      series = described_class.call(from: from, to: to)

      expect(series["2026-06-01"]).to eq(1_150.0)
      expect(described_class.call(from: from, to: to, account_ids: [ other.id ])["2026-06-05"]).to eq(150.0)
    end
  end
end
