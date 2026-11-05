# typed: strict

module Api
  module Render
    class Subscription < Api::Render::Base
      extend T::Sig

      # Index rows: each series plus its trailing timeline slice, batched
      # through TimelineQuery so the listing never loads full histories.
      sig { params(series: T::Array[::RecurringSeries]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index(series)
        timelines = ::Recurring::TimelineQuery.call(series.map(&:id))
        series.map { |s| serialize(s).merge(timeline: timeline(timelines[s.id] || [])) }
      end

      # The show shape: the series plus its full occurrence history with
      # linked-transaction context.
      sig { params(series: ::RecurringSeries).returns(T::Hash[Symbol, T.untyped]) }
      def detail(series)
        occurrences = series.recurring_occurrences.chronological.includes(cash_transaction: :account)
        serialize(series).merge(
          occurrences: occurrences.map { |o| occurrence(o, with_transaction: true) }
        )
      end

      sig { params(month: Date, occurrences: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def calendar(month, occurrences)
        {
          month: month.strftime("%Y-%m"),
          occurrences: occurrences.map do |o|
            series = T.must(o.recurring_series)
            occurrence(o).merge(series_id: series.id, name: series.name)
          end
        }
      end

      sig { params(occurrences: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def upcoming(occurrences)
        {
          upcoming: occurrences.map do |o|
            {
              occurrence_id: o.id,
              series_id: o.recurring_series_id,
              name: T.must(o.recurring_series).name,
              expected_date: o.expected_date,
              expected_amount: o.expected_amount&.to_f,
              status: o.status
            }
          end
        }
      end

      sig { params(s: ::RecurringSeries).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(s)
        {
          id: s.id,
          name: s.name,
          status: s.status,
          source: s.source,
          kind: s.kind,
          merchant_id: s.merchant_id,
          description_pattern: s.description_pattern,
          granularity: s.granularity,
          quantity: s.quantity,
          anchor: s.anchor,
          cadence_description: s.cadence_description,
          average_amount: s.average_amount.to_f,
          last_amount: s.last_amount&.to_f,
          min_amount: s.min_amount&.to_f,
          max_amount: s.max_amount&.to_f,
          amount_tolerance: s.amount_tolerance.to_f,
          monthly_equivalent: s.monthly_equivalent.round(2),
          annual_equivalent: (s.monthly_equivalent * 12).round(2),
          confidence: s.confidence.round(3),
          confidence_label: confidence_label(s.confidence),
          first_charge_date: s.first_charge_date,
          last_charge_date: s.last_charge_date,
          next_expected_date: s.next_expected_date,
          occurrences_count: s.occurrences_count,
          misses_streak: s.misses_streak,
          at_risk: s.at_risk?,
          price_changed_recently: s.last_price_change_at.present? && T.must(s.last_price_change_at) > 31.days.ago,
          notes: s.notes,
          accepted_at: s.accepted_at,
          dismissed_at: s.dismissed_at,
          ended_at: s.ended_at
        }
      end

      sig { params(o: ::RecurringOccurrence, with_transaction: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def occurrence(o, with_transaction: false)
        json = {
          id: o.id,
          expected_date: o.expected_date,
          status: o.status,
          charged_date: o.charged_date,
          amount: o.amount&.to_f,
          expected_amount: o.expected_amount&.to_f,
          amount_delta: o.amount_delta,
          cash_transaction_id: o.cash_transaction_id
        }
        if with_transaction && o.cash_transaction
          txn = T.must(o.cash_transaction)
          json[:transaction] = {
            id: txn.id,
            description: txn.description,
            account_name: txn.account&.name
          }
        end
        json
      end

      private

      # Same shape as before: settled ascending by expected_date, then the
      # next pending occurrence appended.
      sig { params(rows: T::Array[::RecurringOccurrence]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def timeline(rows)
        pending, settled = rows.partition { |o| ::RecurringOccurrence::PENDING_STATUSES.include?(o.status) }
        ordered = settled.sort_by(&:expected_date) + pending.sort_by(&:expected_date).first(1)
        ordered.map { |o| occurrence(o) }
      end

      # value may arrive as BigDecimal (decimal column) — Numeric keeps the
      # runtime sig honest either way.
      sig { params(value: Numeric).returns(String) }
      def confidence_label(value)
        case value
        when 0.85.. then "high"
        when 0.6...0.85 then "medium"
        else "low"
        end
      end
    end
  end
end
