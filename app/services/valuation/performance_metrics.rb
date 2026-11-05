# typed: strict

module Valuation
  # Pure return math over a daily value series and dated external cash
  # flows. Two complementary answers, per industry convention:
  #
  # - TWR (time-weighted): geometric linking of daily returns with flows
  #   removed — "how good were the picks", comparable to a benchmark.
  # - XIRR (money-weighted): the discount rate that zeroes the dated flow
  #   NPV — "what did my money actually earn", rewards/penalizes timing.
  #
  # `values` maps date => portfolio value (ascending or not — sorted here).
  # `flows` maps date => signed external flow into the tracked pool
  # (buys/transfers-in positive, sells/transfers-out/dividends negative).
  class PerformanceMetrics
    extend T::Sig

    sig { params(values: T::Hash[Date, Float], flows: T::Hash[Date, Float]).void }
    def initialize(values:, flows: {})
      @dates  = T.let(values.keys.sort, T::Array[Date])
      @values = T.let(values, T::Hash[Date, Float])
      @flows  = T.let(flows, T::Hash[Date, Float])
    end

    sig { returns(T.nilable(Float)) }
    def start_value
      first = @dates.first
      first && @values[first]
    end

    sig { returns(T.nilable(Float)) }
    def end_value
      last = @dates.last
      last && @values[last]
    end

    sig { returns(Float) }
    def net_flows
      window = T.let(@dates.first, T.nilable(Date))
      return 0.0 if window.nil?

      @flows.sum(0.0) { |date, amount| date > window && date <= T.must(@dates.last) ? amount : 0.0 }
    end

    # Daily-linked TWR with the flow-at-start convention:
    #   r_d = V_d / (V_prev + F_d) - 1
    # Days where the denominator is non-positive (value gaps, full
    # liquidation) contribute no return instead of a nonsense factor.
    sig { returns(T.nilable(Float)) }
    def twr
      return nil if @dates.size < 2

      growth = 1.0
      @dates.each_cons(2) do |pair|
        prev_date = T.must(pair.first)
        date      = T.must(pair.last)
        base      = T.must(@values[prev_date]) + flow_between(prev_date, date)
        next if base <= 0

        growth *= T.must(@values[date]) / base
      end
      growth - 1.0
    end

    # (1+TWR)^(365/days) - 1. Sub-year windows are returned unannualized
    # (annualizing a hot quarter fabricates a rate nobody earned).
    sig { returns(T.nilable(Float)) }
    def twr_annualized
      total = twr
      return nil if total.nil?

      days = (T.must(@dates.last) - T.must(@dates.first)).to_i
      return total if days < 365

      ((1.0 + total)**(365.0 / days)) - 1.0
    end

    # Money-weighted return via bisection on the XIRR NPV (robust where
    # Newton diverges on sign-flipping flow patterns). Investor-perspective
    # flows: opening value and contributions are money in (negative),
    # withdrawals and the closing value are money out (positive).
    sig { returns(T.nilable(Float)) }
    def xirr
      first = @dates.first
      last  = @dates.last
      return nil if first.nil? || last.nil? || first == last

      cashflows = [ [ first, -T.must(start_value) ] ]
      @flows.each do |date, amount|
        next if amount.zero? || date <= first || date > last

        cashflows << [ date, -amount ]
      end
      cashflows << [ last, T.must(end_value) ]

      # An IRR only exists when money moved both ways.
      cashflows = cashflows.reject { |_, amount| amount.zero? }
      return nil unless cashflows.any? { |_, a| a.positive? } && cashflows.any? { |_, a| a.negative? }

      solve_rate(cashflows, origin: first)
    end

    private

    # Net external flow on the open interval (prev, current] — daily series
    # normally make this a single day's flow, but sparse series (weekends,
    # gaps) fold the intervening days into the next return.
    sig { params(prev_date: Date, date: Date).returns(Float) }
    def flow_between(prev_date, date)
      @flows.sum(0.0) { |d, amount| d > prev_date && d <= date ? amount : 0.0 }
    end

    MAX_RATE = 100.0
    MIN_RATE = -0.9999

    sig do
      params(cashflows: T::Array[[ Date, Float ]], origin: Date).returns(T.nilable(Float))
    end
    def solve_rate(cashflows, origin:)
      npv = ->(rate) do
        cashflows.sum do |date, amount|
          amount / ((1.0 + rate)**((date - origin).to_f / 365.0))
        end
      end

      lo = MIN_RATE
      hi = MAX_RATE
      f_lo = npv.call(lo)
      f_hi = npv.call(hi)
      return nil if f_lo * f_hi > 0 # no sign change — no meaningful IRR

      100.times do
        mid = (lo + hi) / 2.0
        f_mid = npv.call(mid)
        return mid if f_mid.abs < 1e-9

        if f_lo * f_mid < 0
          hi = mid
        else
          lo = mid
          f_lo = f_mid
        end
      end
      (lo + hi) / 2.0
    end
  end
end
