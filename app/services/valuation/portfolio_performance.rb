# typed: strict

module Valuation
  # Assembles PerformanceMetrics inputs for the household portfolio: the
  # honest daily value series (PortfolioSeries) plus dated external flows
  # from the investment ledger. The tracked pool is securities only — cash
  # is not valued — so money crossing its boundary is:
  #
  #   in:  purchases and transfers-in (cost when known, else trade amount)
  #   out: sales, transfers-out, and dividends (income leaves as cash)
  class PortfolioPerformance
    extend T::Sig

    sig { params(from: Date, to: Date).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(from:, to: Date.current)
      series = PortfolioSeries.call_with_flows(from: from, to: to)
      values = T.let(series[:values].transform_keys { |d| Date.parse(d) }, T::Hash[Date, Float])
      return empty_payload(from, to) if values.size < 2

      # The engine's own adjustments (a custodian exit, a holding dropping
      # out when its prices stop) change the value with no ledger trade;
      # counting them as flows keeps them from reading as gains or losses.
      external = flows(from, to)
      series[:flows].each { |date, amount| external[date] = external.fetch(date, 0.0) + amount }

      metrics = PerformanceMetrics.new(values: values, flows: external)
      window_days = (T.must(values.keys.max) - T.must(values.keys.min)).to_i

      {
        from:               T.must(values.keys.min).to_s,
        to:                 T.must(values.keys.max).to_s,
        start_value:        metrics.start_value&.round(2),
        end_value:          metrics.end_value&.round(2),
        net_external_flows: metrics.net_flows.round(2),
        twr_pct:            to_pct(sane(metrics.twr)),
        twr_annualized_pct: to_pct(sane(metrics.twr_annualized)),
        # XIRR is an annualized rate by construction — over a few weeks it
        # extrapolates noise into three-digit rates, so short windows skip it.
        xirr_pct:           window_days >= MIN_XIRR_WINDOW_DAYS ? to_pct(sane(metrics.xirr)) : nil
      }
    end

    MIN_XIRR_WINDOW_DAYS = 90

    # Portfolio-level returns beyond ±1000% almost always mean the value
    # series is broken (a price backfill gap valuing the portfolio near
    # zero for part of the window), not a real return — suppress rather
    # than display nonsense.
    MAX_PLAUSIBLE_RETURN = T.let(10.0, Float)

    sig { params(value: T.nilable(Float)).returns(T.nilable(Float)) }
    def self.sane(value)
      value.nil? || value.abs > MAX_PLAUSIBLE_RETURN ? nil : value
    end
    private_class_method :sane

    sig { params(from: Date, to: Date).returns(T::Hash[Date, Float]) }
    def self.flows(from, to)
      ledger = InvestmentTransaction
        .joins(:transaction_type)
        .where(trade_date: from..to)

      flows = T.let(Hash.new(0.0), T::Hash[Date, Float])

      ledger
        .where(transaction_types: { category: Positions::Rebuild::INBOUND_CATEGORIES })
        .group(:trade_date)
        .sum(Arel.sql("ABS(COALESCE(cost_usd, amount_usd, 0))"))
        .each { |date, amount| flows[date] = flows.fetch(date, 0.0) + amount.to_f }

      ledger
        .where(transaction_types: { category: Positions::Rebuild::OUTBOUND_CATEGORIES })
        .group(:trade_date)
        .sum(Arel.sql("ABS(COALESCE(amount_usd, cost_usd, 0))"))
        .each { |date, amount| flows[date] = flows.fetch(date, 0.0) - amount.to_f }

      ledger.dividends
        .group(:trade_date)
        .sum(:income_usd)
        .each { |date, amount| flows[date] = flows.fetch(date, 0.0) - amount.to_f }

      flows
    end
    private_class_method :flows

    sig { params(value: T.nilable(Float)).returns(T.nilable(Float)) }
    def self.to_pct(value)
      value.nil? ? nil : (value * 100).round(2).to_f
    end
    private_class_method :to_pct

    sig { params(from: Date, to: Date).returns(T::Hash[Symbol, T.untyped]) }
    def self.empty_payload(from, to)
      {
        from: from.to_s, to: to.to_s,
        start_value: nil, end_value: nil, net_external_flows: 0.0,
        twr_pct: nil, twr_annualized_pct: nil, xirr_pct: nil
      }
    end
    private_class_method :empty_payload
  end
end
