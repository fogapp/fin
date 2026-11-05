# typed: strict

module Recurring
  # Hypothesize-and-verify cadence inference. Given a set of charge dates:
  # generate candidate schedules from the median inter-charge gap (weekly,
  # biweekly, monthly on day N / last day / Nth weekday, bimonthly,
  # quarterly, semiannual, yearly), verify each by materializing its expected
  # dates across the observed span and matching actual dates within the
  # schedule's jitter tolerance, then keep the best-scoring candidate.
  #
  # Confidence is a backtest: fit the schedule on the earlier ~70% of matched
  # dates, score by how well it predicts the holdout — coincidental clusters
  # predict poorly, real subscriptions predict well.
  class CadenceDetector
    extend T::Sig

    MIN_HITS        = 3
    MIN_HITS_ANNUAL = 2
    MIN_HIT_RATE    = 0.8

    class Result < T::Struct
      const :schedule, Recurring::Schedule
      const :matches, T::Hash[Date, Date] # expected date => actual charge date
      const :missed_dates, T::Array[Date] # interior expected dates with no charge
      const :hit_rate, Float
      const :confidence, Float
    end

    sig { params(dates: T::Array[Date]).returns(T.nilable(Result)) }
    def self.detect(dates)
      new(dates).detect
    end

    sig { params(dates: T::Array[Date]).void }
    def initialize(dates)
      @dates = T.let(dates.sort.uniq, T::Array[Date])
    end

    sig { returns(T.nilable(Result)) }
    def detect
      return nil if @dates.size < 2

      gaps = @dates.each_cons(2).map { |a, b| (T.must(b) - T.must(a)).to_i }
      candidates = candidate_schedules(median(gaps))
      candidates.filter_map { |s| verify(s) }.max_by { |r| [ r.hit_rate, r.confidence ] }
    end

    private

    sig { params(gap: Numeric).returns(T::Array[Recurring::Schedule]) }
    def candidate_schedules(gap)
      case gap
      when 4..10   then [ weekly(1) ]
      when 11..17  then [ weekly(2) ]
      when 18..45  then [ monthly(1), nth_weekday_monthly ].compact
      when 46..75  then [ monthly(2) ]
      when 76..120 then [ monthly(3) ]
      when 121..250 then [ monthly(6) ]
      when 300..430 then [ yearly ]
      else []
      end
    end

    sig { params(quantity: Integer).returns(Recurring::Schedule) }
    def weekly(quantity)
      Schedule.new(granularity: Schedule::Granularity::Week, quantity: quantity, anchor: { "weekday" => modal_weekday })
    end

    sig { params(quantity: Integer).returns(Recurring::Schedule) }
    def monthly(quantity)
      Schedule.new(granularity: Schedule::Granularity::Month, quantity: quantity, anchor: day_of_month_anchor)
    end

    sig { returns(T.nilable(Recurring::Schedule)) }
    def nth_weekday_monthly
      pairs = @dates.map { |d| [ ((d.day - 1) / 7) + 1, d.wday ] }
      mode, count = pairs.tally.max_by { |_, c| c }
      return nil unless mode && count && count >= (@dates.size * 0.6).ceil

      Schedule.new(granularity: Schedule::Granularity::Month, anchor: { "nth_weekday" => mode })
    end

    sig { returns(Recurring::Schedule) }
    def yearly
      mode = @dates.map { |d| [ d.month, d.day ] }.tally.max_by { |_, c| c }&.first || [ T.must(@dates.last).month, T.must(@dates.last).day ]
      Schedule.new(granularity: Schedule::Granularity::Year, anchor: { "month" => mode[0], "day" => mode[1] })
    end

    sig { returns(Integer) }
    def modal_weekday
      @dates.map(&:wday).tally.max_by { |_, c| c }&.first || 0
    end

    # Circular median of day-of-month (31-day circle, so [30, 31, 1, 2]
    # clusters correctly), with a "last day" override when charges hug each
    # month's end.
    sig { returns(T::Hash[String, T.untyped]) }
    def day_of_month_anchor
      end_huggers = @dates.count { |d| d.end_of_month.day - d.day <= 2 }
      return { "day_of_month" => "last" } if end_huggers >= (@dates.size * 0.6).ceil && @dates.map(&:day).min.to_i >= 26

      best = (1..31).min_by do |candidate|
        @dates.sum { |d| circular_distance(d.day, candidate) }
      end
      { "day_of_month" => best }
    end

    sig { params(a: Integer, b: Integer).returns(Integer) }
    def circular_distance(a, b)
      raw = (a - b).abs
      [ raw, 31 - raw ].min
    end

    sig { params(schedule: Recurring::Schedule).returns(T.nilable(Result)) }
    def verify(schedule)
      tol = schedule.tolerance_days
      seed = snap_seed(schedule)
      expected = [ seed ] + schedule.dates_between(seed, T.must(@dates.last) + tol)

      available = @dates.dup
      matches = {}
      expected.each do |exp|
        best = available.min_by { |d| (d - exp).to_i.abs }
        next unless best && (best - exp).to_i.abs <= tol

        matches[exp] = best
        available.delete(best)
      end

      min_hits = schedule.granularity == Schedule::Granularity::Year ? MIN_HITS_ANNUAL : MIN_HITS
      return nil if matches.size < min_hits

      hit_rate = matches.size.to_f / expected.size
      return nil if hit_rate < MIN_HIT_RATE

      missed = expected.select { |e| !matches.key?(e) && e < matches.keys.max }
      Result.new(
        schedule: schedule,
        matches: matches,
        missed_dates: missed,
        hit_rate: hit_rate.round(3).to_f,
        confidence: confidence(schedule, matches.values.sort, hit_rate)
      )
    end

    # Weekly schedules propagate seed jitter (advance preserves the seed's
    # weekday), so snap the seed onto the anchor weekday first. Month/year
    # anchors self-correct via apply_month_anchor.
    sig { params(schedule: Recurring::Schedule).returns(Date) }
    def snap_seed(schedule)
      seed = T.must(@dates.first)
      return seed unless schedule.granularity == Schedule::Granularity::Week && schedule.anchor["weekday"]

      delta = (schedule.anchor["weekday"] - seed.wday) % 7
      delta -= 7 if delta > 3
      seed + delta
    end

    sig { params(schedule: Recurring::Schedule, matched: T::Array[Date], hit_rate: Float).returns(Float) }
    def confidence(schedule, matched, hit_rate)
      return (hit_rate * 0.8).round(3).to_f if matched.size < 3

      fit_n = [ [ (matched.size * 0.7).ceil, 2 ].max, matched.size - 1 ].min
      seed = T.must(matched[fit_n - 1])
      holdout = T.must(matched[fit_n..])
      tol = schedule.tolerance_days

      predicted = schedule.dates_between(seed, T.must(matched.last) + tol)
      return (hit_rate * 0.8).round(3).to_f if predicted.empty?

      hits = predicted.count { |p| holdout.any? { |h| (h - p).to_i.abs <= tol } }
      ((hit_rate * 0.5) + (hits.to_f / predicted.size * 0.5)).round(3).to_f
    end

    sig { params(values: T::Array[Integer]).returns(Numeric) }
    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? T.must(sorted[mid]) : (T.must(sorted[mid - 1]) + T.must(sorted[mid])) / 2.0
    end
  end
end
