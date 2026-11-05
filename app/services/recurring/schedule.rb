# typed: strict

module Recurring
  # Cadence math shared by detection, matching, and forecasting. A schedule is
  # granularity (week | month | year) + quantity (every N) + an anchor:
  #
  #   {"weekday" => 5}                weekly-family, 0=Sunday..6=Saturday
  #   {"day_of_month" => 15}         monthly-family, clamped to month length
  #   {"day_of_month" => "last"}     monthly-family, last day of month
  #   {"nth_weekday" => [3, 5]}      monthly-family, 3rd Friday (5th = last)
  #   {"month" => 11, "day" => 3}    yearly
  #
  # Schedules are seeded, not absolutely anchored: occurrence N+1 is derived
  # by advancing occurrence N, so the phase (which weeks, which months) comes
  # from the seed date. Callers seed from last_charge_date.
  class Schedule
    extend T::Sig

    # The base unit a schedule repeats on.
    class Granularity < T::Enum
      extend T::Sig

      include ApplicationEnum

      enums do
        Week = new("week")
        Month = new("month")
        Year = new("year")
      end
    end

    # Date jitter accepted when matching a transaction to an expected date.
    TOLERANCE_DAYS = T.let(
      { Granularity::Week => 2, Granularity::Month => 4, Granularity::Year => 14 }.freeze,
      T::Hash[Granularity, Integer]
    )

    sig { returns(Granularity) }
    attr_reader :granularity

    sig { returns(Integer) }
    attr_reader :quantity

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :anchor

    sig { params(granularity: Granularity, quantity: Integer, anchor: T::Hash[String, T.untyped]).void }
    def initialize(granularity:, quantity: 1, anchor: {})
      raise ArgumentError, "quantity must be positive" unless quantity.positive?

      @granularity = granularity
      @quantity = quantity
      @anchor = T.let(anchor.stringify_keys, T::Hash[String, T.untyped])
    end

    sig { returns(Integer) }
    def tolerance_days
      TOLERANCE_DAYS.fetch(granularity)
    end

    sig { returns(Float) }
    def periods_per_year
      base = { Granularity::Week => 52.0, Granularity::Month => 12.0, Granularity::Year => 1.0 }.fetch(granularity)
      base / quantity
    end

    # The expected date immediately following `date` (one period later).
    sig { params(date: Date).returns(Date) }
    def advance(date)
      case granularity
      when Granularity::Week then date + (7 * quantity)
      when Granularity::Month then apply_month_anchor(date >> quantity)
      else
        anchored = anchor["month"] && anchor["day"] ? safe_date(date.year + quantity, anchor["month"], anchor["day"]) : (date >> (12 * quantity))
        anchored > date ? anchored : safe_date(date.year + quantity, date.month, date.day)
      end
    end

    # The first anchored date on or after `date` (for seeding a schedule that
    # has no charge history yet, e.g. manual creation).
    sig { params(date: Date).returns(Date) }
    def next_on_or_after(date)
      case granularity
      when Granularity::Week
        anchor["weekday"] ? date + ((anchor["weekday"] - date.wday) % 7) : date
      when Granularity::Month
        candidate = apply_month_anchor(date)
        candidate >= date ? candidate : apply_month_anchor(date >> quantity)
      else
        candidate = safe_date(date.year, anchor["month"] || date.month, anchor["day"] || date.day)
        candidate >= date ? candidate : safe_date(date.year + quantity, anchor["month"] || date.month, anchor["day"] || date.day)
      end
    end

    # Expected dates strictly after `seed`, up to and including `until_date`.
    sig { params(seed: Date, until_date: Date, limit: Integer).returns(T::Array[Date]) }
    def dates_between(seed, until_date, limit: 400)
      dates = T.let([], T::Array[Date])
      cursor = advance(seed)
      while cursor <= until_date && dates.size < limit
        dates << cursor
        cursor = advance(cursor)
      end
      dates
    end

    sig { returns(String) }
    def description
      every = quantity == 1 ? nil : quantity
      case granularity
      when Granularity::Week
        day = anchor["weekday"] ? Date::DAYNAMES[anchor["weekday"] % 7] : nil
        base = every ? "Every #{every} weeks" : "Weekly"
        day ? "#{base} on #{day}" : base
      when Granularity::Month
        base = every ? "Every #{every} months" : "Monthly"
        "#{base} #{month_anchor_phrase}".strip
      else
        base = every ? "Every #{every} years" : "Yearly"
        anchor["month"] && anchor["day"] ? "#{base} on #{Date::ABBR_MONTHNAMES[anchor['month']]} #{anchor['day']}" : base
      end
    end

    private

    sig { returns(String) }
    def month_anchor_phrase
      if anchor["day_of_month"] == "last"
        "on the last day"
      elsif anchor["day_of_month"]
        "on the #{anchor['day_of_month'].to_i.ordinalize}"
      elsif anchor["nth_weekday"]
        nth, wday = anchor["nth_weekday"]
        label = nth >= 5 ? "last" : nth.ordinalize
        "on the #{label} #{Date::DAYNAMES[wday % 7]}"
      else
        ""
      end
    end

    sig { params(month_start: Date).returns(Date) }
    def apply_month_anchor(month_start)
      first = Date.new(month_start.year, month_start.month, 1)
      if anchor["day_of_month"] == "last"
        first.end_of_month
      elsif anchor["day_of_month"]
        day = anchor["day_of_month"].to_i
        [ first + (day - 1), first.end_of_month ].min
      elsif anchor["nth_weekday"]
        nth, wday = anchor["nth_weekday"]
        candidate = first + ((wday - first.wday) % 7) + ((nth - 1) * 7)
        candidate.month == first.month ? candidate : candidate - 7
      else
        month_start
      end
    end

    sig { params(year: Integer, month: Integer, day: Integer).returns(Date) }
    def safe_date(year, month, day)
      last = Date.new(year, month, 1).end_of_month.day
      Date.new(year, month, [ day, last ].min)
    end
  end
end
