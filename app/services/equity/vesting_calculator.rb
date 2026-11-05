# typed: strict

module Equity
  # Expands a grant's schedule into ordered tranches [{date:, quantity:}] and
  # answers vested/unvested/next-vest questions as of any date.
  #
  # Three schedule shapes, in precedence order:
  #   1. custom_tranches — used verbatim (sorted by date), flat fields ignored
  #   2. flat interval × occurrences, with cumulative rounding so the tranche
  #      quantities sum to exactly the grant quantity (5-4-5-4 style splits,
  #      never drifting), and an optional cliff that merges the first N
  #      installments into one tranche dated at installment N
  #   3. no schedule at all — a single fully-vested tranche at the
  #      vesting commencement date
  #
  # Cancellation events reduce quantity from the unvested tail first (latest
  # tranches shaved first), spilling into vested tranches only when exhausted.
  class VestingCalculator
    extend T::Sig

    ROUND_SCALE = 4

    INTERVAL_MONTHS = T.let({
      EquityGrant::VestingInterval::Monthly   => 1,
      EquityGrant::VestingInterval::Quarterly => 3,
      EquityGrant::VestingInterval::Annual    => 12
    }.freeze, T::Hash[EquityGrant::VestingInterval, Integer])

    sig { params(grant: EquityGrant).void }
    def initialize(grant)
      @grant = grant
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def tranches
      @tranches ||= T.let(apply_cancellations(raw_tranches), T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
    end

    sig { params(as_of: Date).returns(BigDecimal) }
    def vested_quantity(as_of = Date.current)
      tranches.select { |t| t[:date] <= as_of }.sum(BigDecimal("0")) { |t| t[:quantity] }
    end

    sig { params(as_of: Date).returns(BigDecimal) }
    def unvested_quantity(as_of = Date.current)
      tranches.select { |t| t[:date] > as_of }.sum(BigDecimal("0")) { |t| t[:quantity] }
    end

    sig { params(as_of: Date).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def next_vest(as_of = Date.current)
      tranches.find { |t| t[:date] > as_of }
    end

    private

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def raw_tranches
      return custom_tranches if @grant.custom_tranches.present?

      quantity = @grant.quantity.to_d
      start    = @grant.vesting_commencement_date || @grant.grant_date
      n        = @grant.vesting_occurrences.to_i
      return [ { date: start, quantity: quantity } ] if n <= 0

      cumulative_prev = T.let(BigDecimal("0"), BigDecimal)
      installments = (1..n).map do |i|
        # Final installment takes quantity − cum_{n−1} so the sum is exact.
        cumulative = i == n ? quantity : (quantity * i / n).round(ROUND_SCALE)
        tranche = { date: installment_date(start, i), quantity: cumulative - cumulative_prev }
        cumulative_prev = cumulative
        tranche
      end
      merge_cliff(installments)
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def custom_tranches
      Array(@grant.custom_tranches)
        .map { |t| { date: Date.iso8601(t["date"].to_s), quantity: t["quantity"].to_d } }
        .sort_by { |t| t[:date] }
    end

    # Rails' Date#>> clamps day-of-month (Jan 31 >> 1 == Feb 28/29), which is
    # exactly the convention vesting schedules use.
    sig { params(start: Date, installment: Integer).returns(Date) }
    def installment_date(start, installment)
      interval = @grant.vesting_interval
      months = interval.nil? ? 1 : INTERVAL_MONTHS.fetch(interval, 1)
      start >> (months * installment)
    end

    sig { params(installments: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def merge_cliff(installments)
      cliff = [ @grant.cliff_installments.to_i, installments.size ].min
      return installments if cliff <= 1

      head = installments.first(cliff)
      merged = { date: T.must(head.last)[:date], quantity: head.sum(BigDecimal("0")) { |t| t[:quantity] } }
      [ merged ] + installments.drop(cliff)
    end

    sig { params(list: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def apply_cancellations(list)
      remaining = cancelled_quantity
      return list unless remaining.positive?

      result = []
      list.reverse_each do |tranche|
        if remaining >= tranche[:quantity]
          remaining -= tranche[:quantity]
        elsif remaining.positive?
          result.unshift(date: tranche[:date], quantity: tranche[:quantity] - remaining)
          remaining = BigDecimal("0")
        else
          result.unshift(tranche)
        end
      end
      result
    end

    sig { returns(BigDecimal) }
    def cancelled_quantity
      events = @grant.events
      if events.loaded?
        events.select { |e| e.kind == EquityGrantEvent::Kind::Cancellation }.sum(BigDecimal("0")) { |e| e.quantity.to_d }
      else
        events.where(kind: EquityGrantEvent::Kind::Cancellation).sum(:quantity).to_d
      end
    end
  end
end
