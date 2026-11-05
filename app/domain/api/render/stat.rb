# typed: strict

module Api
  module Render
    # Read side of the Stats system. Serves the precomputed metric_points
    # store only — no raw-data recomputation on the read path, with one
    # exception: the optional per-metric breakdowns on show (a single
    # indexed grouped query, same cost class as any cashflow drilldown).
    #
    # Date encoding: monthly metrics use "YYYY-MM" (the chart system and
    # transactions drill-through key off the 7-char form), daily use ISO
    # "YYYY-MM-DD".
    #
    # Partial periods: the current month (monthly) / today (daily) is
    # in-flight — flagged partial, and for flow metrics change_pct is
    # pace-adjusted (the stored MTD value is projected to a full month
    # before comparing against the prior period, so "spend down 60%" on the
    # 3rd of the month doesn't lie). pace carries the projection itself.
    class Stat < Api::Render::Base
      extend T::Sig

      SPARKLINE_MONTHS = 13
      SPARKLINE_DAYS   = 90
      DEFAULT_RANGE_MONTHS = 24
      DEFAULT_RANGE_DAYS   = 365

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def index
        today = Date.current
        window_from = [ (today << (SPARKLINE_MONTHS - 1)).beginning_of_month, today - SPARKLINE_DAYS ].min

        points_by_key = MetricPoint
          .where(metric_key: Metrics::Registry.all.map { |d| d.key.to_s })
          .where(date: window_from..)
          .ordered
          .group_by(&:metric_key)

        {
          as_of:  MetricPoint.maximum(:computed_at),
          groups: Metrics::Registry::GROUPS,
          stats:  Metrics::Registry.all.map { |dc| index_entry(dc, points_by_key[dc.key.to_s] || [], today) }
        }
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def show
        definition_class = Metrics::Registry.find(params[:key].to_s)
        return nil if definition_class.nil?

        today = Date.current
        monthly = definition_class.granularity == Metrics::Granularity::Month
        default_from = monthly ? (today << DEFAULT_RANGE_MONTHS).beginning_of_month : today - DEFAULT_RANGE_DAYS
        from = date_param(:from) || default_from
        from = from.beginning_of_month if monthly
        to = date_param(:to) || today

        points = MetricPoint.for_key(definition_class.key).in_range(from..to).ordered.to_a

        meta(definition_class).merge(
          range:      { from: from.iso8601, to: to.iso8601 },
          series:     points.map { |p| serialize_point(definition_class, p, today) },
          summary:    summary(definition_class, points, today),
          breakdowns: definition_class.new.breakdowns(from: from, to: to),
          drill:      definition_class.drill
        )
      end

      private

      sig { params(definition_class: T.class_of(Metrics::Definition)).returns(T::Hash[Symbol, T.untyped]) }
      def meta(definition_class)
        {
          key:         definition_class.key.to_s,
          label:       definition_class.label,
          description: definition_class.description,
          group:       definition_class.group.to_s,
          unit:        definition_class.unit.to_s,
          granularity: definition_class.granularity.to_s,
          value_type:  definition_class.value_type.to_s,
          direction:   definition_class.direction.to_s
        }
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), points: T::Array[MetricPoint], today: Date).returns(T::Hash[Symbol, T.untyped]) }
      def index_entry(definition_class, points, today)
        sparkline_from = if definition_class.granularity == Metrics::Granularity::Month
          (today << (SPARKLINE_MONTHS - 1)).beginning_of_month
        else
          today - SPARKLINE_DAYS
        end
        window = points.select { |p| p.date >= sparkline_from }

        latest   = window.last
        previous = previous_point(definition_class, window)

        meta(definition_class).merge(
          latest:     latest && serialize_point(definition_class, latest, today),
          previous:   previous && serialize_point(definition_class, previous, today),
          change_pct: change_pct(definition_class, latest, previous, today),
          pace:       pace(definition_class, latest, previous, today),
          sparkline:  window.map { |p| { date: encode_date(definition_class, p.date), value: round(p.value) } },
          drill:      definition_class.drill
        )
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), points: T::Array[MetricPoint], today: Date).returns(T::Hash[Symbol, T.untyped]) }
      def summary(definition_class, points, today)
        latest   = points.last
        previous = previous_point(definition_class, points)

        # Honesty: the in-flight period is excluded from min/max/avg for
        # flows — a 3-day-old month would otherwise always be the "min".
        complete = points.reject { |p| p.value.nil? || (flow?(definition_class) && partial?(definition_class, p.date, today)) }
        min_p = complete.min_by { |p| p.value.to_f }
        max_p = complete.max_by { |p| p.value.to_f }

        {
          latest:     latest && serialize_point(definition_class, latest, today),
          previous:   previous && serialize_point(definition_class, previous, today),
          change_pct: change_pct(definition_class, latest, previous, today),
          pace:       pace(definition_class, latest, previous, today),
          min:        min_p && { date: encode_date(definition_class, min_p.date), value: round(min_p.value) },
          max:        max_p && { date: encode_date(definition_class, max_p.date), value: round(max_p.value) },
          avg:        complete.any? ? (complete.sum { |p| p.value.to_f } / complete.size).round(2) : nil,
          changes:    changes(definition_class, points, today)
        }
      end

      # The comparison anchor: for flows the last complete period; for levels
      # the nearest point at least a month back (day-over-day is noise).
      sig { params(definition_class: T.class_of(Metrics::Definition), points: T::Array[MetricPoint]).returns(T.nilable(MetricPoint)) }
      def previous_point(definition_class, points)
        latest = points.last
        return nil if latest.nil?

        if flow?(definition_class)
          points[-2]
        else
          anchor = latest.date << 1
          points.select { |p| p.date <= anchor }.last
        end
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), latest: T.nilable(MetricPoint), previous: T.nilable(MetricPoint), today: Date).returns(T.untyped) }
      def change_pct(definition_class, latest, previous, today)
        return nil if latest.nil? || previous.nil? || latest.value.nil? || previous.value.nil?

        current = latest.value.to_f
        if flow?(definition_class) && partial?(definition_class, latest.date, today)
          projection = project(definition_class, latest, today)
          return nil if projection.nil?

          current = projection
        end
        pct_change(current, previous.value.to_f)
      end

      # Projection of an in-flight flow period to its full length, from the
      # stored MTD value and how far through the period the computation got.
      sig { params(definition_class: T.class_of(Metrics::Definition), latest: T.nilable(MetricPoint), previous: T.nilable(MetricPoint), today: Date).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def pace(definition_class, latest, previous, today)
        return nil unless flow?(definition_class)
        return nil if latest.nil? || latest.value.nil? || !partial?(definition_class, latest.date, today)

        projection = project(definition_class, latest, today)
        return nil if projection.nil?

        {
          projected:       projection.round(2),
          vs_previous_pct: previous&.value ? pct_change(projection, previous.value.to_f) : nil
        }
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), latest: MetricPoint, today: Date).returns(T.nilable(Float)) }
      def project(definition_class, latest, today)
        return nil unless definition_class.granularity == Metrics::Granularity::Month

        # The stored value covers through the day it was computed (clamped
        # into the current month — a 00:05 run on the 1st covers 1 day).
        computed_on = [ [ latest.computed_at.to_date, latest.date ].max, today ].min
        elapsed = computed_on.day
        days_in_month = latest.date.end_of_month.day
        return nil if elapsed.zero?

        latest.value.to_f / elapsed * days_in_month
      end

      # 1m/3m/ytd/1y change anchors (NetWorthHistory convention). For flows,
      # anchored on the last complete period; for levels, on the latest point.
      sig { params(definition_class: T.class_of(Metrics::Definition), points: T::Array[MetricPoint], today: Date).returns(T::Hash[String, T.untyped]) }
      def changes(definition_class, points, today)
        base = if flow?(definition_class)
          points.reject { |p| partial?(definition_class, p.date, today) }.last
        else
          points.last
        end
        return { "1m" => nil, "3m" => nil, "ytd" => nil, "1y" => nil } if base.nil? || base.value.nil?

        anchors = {
          "1m"  => base.date << 1,
          "3m"  => base.date << 3,
          "ytd" => base.date.beginning_of_year,
          "1y"  => base.date << 12
        }
        anchors.transform_values do |anchor|
          past = points.select { |p| p.date <= anchor && !p.value.nil? }.last
          past && pct_change(base.value.to_f, past.value.to_f)
        end
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), point: MetricPoint, today: Date).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_point(definition_class, point, today)
        {
          date:    encode_date(definition_class, point.date),
          value:   round(point.value),
          partial: partial?(definition_class, point.date, today)
        }
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), date: Date).returns(String) }
      def encode_date(definition_class, date)
        definition_class.granularity == Metrics::Granularity::Month ? date.strftime("%Y-%m") : date.iso8601
      end

      sig { params(definition_class: T.class_of(Metrics::Definition), date: Date, today: Date).returns(T::Boolean) }
      def partial?(definition_class, date, today)
        if definition_class.granularity == Metrics::Granularity::Month
          date == today.beginning_of_month
        else
          date == today
        end
      end

      sig { params(definition_class: T.class_of(Metrics::Definition)).returns(T::Boolean) }
      def flow?(definition_class)
        definition_class.value_type == Metrics::ValueType::Flow
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def round(value)
        value.nil? ? nil : value.to_f.round(2)
      end
    end
  end
end
