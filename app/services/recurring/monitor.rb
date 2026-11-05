# typed: strict

module Recurring
  # Time-based state advancement, run after the Matcher: whatever is still
  # unpaid past its window becomes missed. Active series lapse after
  # LAPSE_AFTER_MISSES consecutive misses; stale unreviewed suggestions are
  # tombstoned (deleted) rather than left rotting in the review queue.
  class Monitor
    extend T::Sig

    # upcoming -> due this many days before the expected date.
    DUE_WINDOW_DAYS = 3
    CONFIDENCE_DECAY = 0.7

    sig { void }
    def self.run
      new.run
    end

    sig { void }
    def run
      advance_active
      sweep_suggestions
    end

    private

    sig { void }
    def advance_active
      RecurringSeries.active.find_each do |series|
        ensure_pending(series)
        tol = series.schedule.tolerance_days

        while series.status == RecurringSeries::Status::Active &&
              (occ = series.recurring_occurrences.pending.chronological.first) &&
              Date.current > occ.expected_date + tol
          miss(series, occ)
        end

        # Row-at-a-time (not update_all): the upcoming → due edge is also the
        # "charge coming up" moment, and publishing on the state edge makes
        # the event once-per-occurrence without any alert bookkeeping.
        series.recurring_occurrences.where(status: RecurringOccurrence::Status::Upcoming)
              .where(expected_date: ..(Date.current + DUE_WINDOW_DAYS))
              .find_each do |occ|
          occ.update!(status: RecurringOccurrence::Status::Due)
          Workflows::Events.publish("subscription.charge_upcoming", subject: series, payload: {
            "name"            => series.name,
            "expected_date"   => occ.expected_date.to_s,
            "expected_amount" => occ.expected_amount.to_f.abs.round(2),
            "days_until"      => [ occ.expected_date.mjd - Date.current.mjd, 0 ].max
          })
        end
      end
    end

    sig { params(series: RecurringSeries, occ: RecurringOccurrence).void }
    def miss(series, occ)
      occ.update!(status: RecurringOccurrence::Status::Missed)
      series.increment!(:misses_streak)
      advance_schedule(series, occ.expected_date)
      Workflows::Events.publish("subscription.payment_missed", subject: series,
                                payload: { "expected_date" => occ.expected_date.to_s })

      return if series.misses_streak < RecurringSeries::LAPSE_AFTER_MISSES

      series.transition_to!(RecurringSeries::Status::Lapsed)
      Workflows::Events.publish("subscription.lapsed", subject: series,
                                payload: { "last_charge_date" => series.last_charge_date&.to_s })
    end

    # Unreviewed suggestions that stop recurring get confidence-decayed on
    # the first miss and deleted on the second (Plaid's EARLY_DETECTION
    # tombstoning): if it isn't charging anymore there is nothing to review.
    sig { void }
    def sweep_suggestions
      RecurringSeries.suggested.find_each do |series|
        tol = series.schedule.tolerance_days

        while series.next_expected_date && Date.current > T.must(series.next_expected_date) + tol
          series.increment!(:misses_streak)
          if series.misses_streak >= RecurringSeries::LAPSE_AFTER_MISSES
            series.destroy!
            break
          end

          series.recurring_occurrences.pending.find_by(expected_date: series.next_expected_date)&.update!(status: RecurringOccurrence::Status::Missed)
          series.update!(confidence: (series.confidence * CONFIDENCE_DECAY).round(3))
          advance_schedule(series, T.must(series.next_expected_date))
        end
      end
    end

    sig { params(series: RecurringSeries, from: Date).void }
    def advance_schedule(series, from)
      next_expected = series.schedule.advance(from)
      series.update!(next_expected_date: next_expected)
      series.recurring_occurrences.find_or_create_by!(expected_date: next_expected) do |o|
        o.status = RecurringOccurrence::Status::Upcoming
        o.expected_amount = series.average_amount
      end
    end

    sig { params(series: RecurringSeries).void }
    def ensure_pending(series)
      return if series.recurring_occurrences.pending.exists?

      from = series.next_expected_date || series.last_charge_date || Date.current
      expected = from > Date.current - series.schedule.tolerance_days ? from : series.schedule.advance(from)
      series.update!(next_expected_date: expected) if series.next_expected_date != expected
      series.recurring_occurrences.find_or_create_by!(expected_date: expected) do |o|
        o.status = RecurringOccurrence::Status::Upcoming
        o.expected_amount = series.average_amount
      end
    end
  end
end
