# typed: strict

module Equity
  # The daily vesting rules for one grant: which workflow events fall due
  # today. Offsets are exact day equalities (14/1 days before a tranche,
  # day-of, 90/30 days before expiration), which keeps a once-a-day scan
  # idempotent without any alert bookkeeping. Returns events rather than
  # publishing them; EquityVestScanJob publishes, with the grant as subject.
  class VestScan
    extend T::Sig

    Event = T.type_alias { [ String, T::Hash[String, T.untyped] ] }

    UPCOMING_OFFSETS_DAYS = T.let([ 14, 1 ].freeze, T::Array[Integer])
    EXPIRING_OFFSETS_DAYS = T.let([ 90, 30 ].freeze, T::Array[Integer])

    sig { params(grant: EquityGrant, today: Date).void }
    def initialize(grant, today: Date.current)
      @grant = grant
      @today = today
    end

    sig { returns(T::Array[Event]) }
    def events
      vest_events + exercise_window_events + expiration_events
    end

    private

    sig { returns(T::Array[Event]) }
    def vest_events
      price = Equity::Valuation.current_share_price(T.must(@grant.equity_company))

      @grant.tranches.filter_map do |tranche|
        type =
          if UPCOMING_OFFSETS_DAYS.any? { |days| tranche[:date] == @today + days }
            "equity.vest_upcoming"
          elsif tranche[:date] == @today
            "equity.vest_occurred"
          end
        next unless type

        value = Equity::Valuation.grant_value(@grant, tranche[:quantity], price)
        [ type, {
          "tranche_date" => tranche[:date].iso8601,
          "quantity"     => tranche[:quantity].to_f,
          "value"        => value&.to_f
        } ]
      end
    end

    # Dec 1 (and only Dec 1): grants exercised this calendar year with unsold
    # shares still have the same-year-sale escape hatch open — a disqualifying
    # sale by Dec 31 erases the entire ISO AMT adjustment.
    sig { returns(T::Array[Event]) }
    def exercise_window_events
      return [] unless @today.month == 12 && @today.day == 1

      exercised_this_year = @grant.events
        .select { |e| e.kind == EquityGrantEvent::Kind::Exercise && e.occurred_on >= @today.beginning_of_year }
        .sum(BigDecimal("0")) { |e| e.quantity.to_d }
      return [] unless exercised_this_year.positive?
      return [] unless @grant.sold_quantity < @grant.exercised_quantity

      [ [ "equity.exercise_window_closing", {
        "year_end"            => Date.new(@today.year, 12, 31).iso8601,
        "exercised_this_year" => exercised_this_year.to_f
      } ] ]
    end

    sig { returns(T::Array[Event]) }
    def expiration_events
      expiration = @grant.expiration_date
      return [] unless expiration && EXPIRING_OFFSETS_DAYS.any? { |days| expiration == @today + days }

      [ [ "equity.grant_expiring", {
        "expiration_date" => expiration.iso8601,
        "days_until"      => expiration.mjd - @today.mjd
      } ] ]
    end
  end
end
