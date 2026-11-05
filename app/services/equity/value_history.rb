# typed: strict

module Equity
  # Turns equity compensation into a carry-forward [date, value] series per
  # company, the same shape RealEstateProperty#value_breakpoints gives net
  # worth.
  #
  # Two inputs move over time and both are stepped, never interpolated:
  #
  #   quantity — tranche vest dates add shares (cancellations are already
  #     baked into VestingCalculator#tranches); exercises and settlements
  #     remove them, because those shares have left the grant and now live in
  #     a brokerage account (public) or as certificated stock (private).
  #     Sales are deliberately ignored — they dispose of shares an exercise or
  #     settlement already removed, so subtracting them would double-count.
  #
  #   price — daily closes for a public company's linked security, the
  #     manually maintained FMV history otherwise. The oldest known price is
  #     carried *backwards* to the start of the window: a private company
  #     whose only 409A is from this year would otherwise show its equity as
  #     worthless for all of last year, which is more wrong than assuming the
  #     price was flat.
  #
  # Value per grant follows Equity::Valuation: options are worth their
  # intrinsic spread, RSU/RSA the full share price. `include_unvested` swaps
  # the vested-only quantity for the whole outstanding grant, counted from the
  # grant date.
  class ValueHistory
    extend T::Sig

    # Extra lookback when loading closes so a window that opens on a weekend
    # or holiday still has a price to carry forward from.
    PRICE_WARMUP_DAYS = 10

    sig { params(from: Date, to: Date, include_unvested: T::Boolean).void }
    def initialize(from:, to: Date.current, include_unvested: false)
      @from = from
      @to = to
      @include_unvested = include_unvested
    end

    # Earliest date any grant could contribute value on — used to widen the
    # "all" net-worth window without building the series first.
    sig { returns(T.nilable(Date)) }
    def self.earliest_date
      EquityGrant.minimum(:grant_date)
    end

    sig { returns(T::Array[EquityCompany]) }
    def companies
      @companies ||= T.let(EquityCompany.includes(:security, :fmv_entries, grants: :events).order(:name).to_a, T.nilable(T::Array[EquityCompany]))
    end

    sig { returns(T::Hash[String, T::Array[[ Date, Float ]]]) }
    def breakpoints_by_company
      companies.to_h { |company| [ company.id, breakpoints_for(company) ] }
    end

    private

    sig { params(company: EquityCompany).returns(T::Array[[ Date, Float ]]) }
    def breakpoints_for(company)
      prices = price_points(company)
      return [] if prices.empty? || company.grants.empty?

      quantities = company.grants.to_h { |grant| [ grant.id, quantity_points(grant) ] }
      dates      = sample_dates(prices, quantities.values.flatten(1))
      return [] if dates.empty?

      price_at = carry_forward(prices, dates)
      qty_at   = quantities.transform_values { |points| carry_forward(points, dates) }

      values = dates.each_with_index.map do |date, i|
        total = company.grants.sum(BigDecimal("0")) do |grant|
          quantity = qty_at.fetch(grant.id)[i]
          next BigDecimal("0") if quantity.nil? || quantity <= 0

          ::Equity::Valuation.grant_value(grant, quantity, price_at[i]) || BigDecimal("0")
        end
        [ date, total.to_f.round(2) ]
      end

      compress(values)
    end

    # Every date the value could change — a vest, an exercise, or a new price
    # — clipped to the window, with the window's opening day always present so
    # carry-forward has a starting point.
    sig { params(prices: T::Array[T.untyped], quantities: T::Array[T.untyped]).returns(T::Array[Date]) }
    def sample_dates(prices, quantities)
      dates = prices.map(&:first) + quantities.map(&:first)
      ([ @from ] + dates.select { |date| date > @from && date <= @to }).uniq.sort
    end

    # [[date, price]] ascending. Public companies price off their linked
    # security's closes and fall back to FMV when nothing is synced yet.
    sig { params(company: EquityCompany).returns(T::Array[T.untyped]) }
    def price_points(company)
      points = []
      security = company.security
      if company.public_company? && security
        points = ::MarketData::PriceSeries
          .daily_closes(security, from: @from - PRICE_WARMUP_DAYS, to: @to)
          .map { |date, close| [ date, close ] }
      end
      points = fmv_points(company) if points.empty?
      return points if points.empty?

      first_date, first_price = points.first
      first_date > @from ? [ [ @from, first_price ] ] + points : points
    end

    sig { params(company: EquityCompany).returns(T::Array[T.untyped]) }
    def fmv_points(company)
      company.fmv_entries
        .sort_by(&:effective_date)
        .map { |entry| [ entry.effective_date, entry.price_per_share.to_d ] }
    end

    # [[date, cumulative_quantity]] for the shares this grant still holds:
    # vested (or, with include_unvested, the whole award) less anything
    # exercised or settled out of it.
    sig { params(grant: EquityGrant).returns(T::Array[T.untyped]) }
    def quantity_points(grant)
      tranches = grant.calculator.tranches
      deltas   = if @include_unvested
        outstanding = tranches.sum(BigDecimal("0")) { |t| t[:quantity] }
        outstanding.positive? ? [ [ grant.grant_date, outstanding ] ] : []
      else
        tranches.map { |tranche| [ tranche[:date], tranche[:quantity] ] }
      end

      deltas += grant.events
        .select { |event| EquityGrantEvent::ACQUIRING_KINDS.include?(event.kind) }
        .map { |event| [ event.occurred_on, -event.quantity.to_d ] }

      running = BigDecimal("0")
      deltas.sort_by(&:first).map { |date, delta| [ date, running += delta ] }
    end

    # Value of the latest point on or before each date; nil until the first
    # point. Both inputs must be sorted ascending.
    sig { params(points: T::Array[T.untyped], dates: T::Array[Date]).returns(T::Array[T.untyped]) }
    def carry_forward(points, dates)
      idx = 0
      current = T.let(nil, T.untyped)
      dates.map do |date|
        while idx < points.size && points[idx][0] <= date
          current = points[idx][1]
          idx += 1
        end
        current
      end
    end

    # A public company contributes one point per trading day; net worth only
    # needs the days the value actually moved.
    sig { params(values: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def compress(values)
      values.each_with_index.select { |(_, value), i| i.zero? || values[i - 1][1] != value }.map(&:first)
    end
  end
end
