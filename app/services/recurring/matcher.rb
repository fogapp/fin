# typed: strict

module Recurring
  # Attaches newly synced transactions to accepted (active/lapsed) series.
  # Accepted series are never re-derived by the Detector — this is the only
  # thing that keeps them current. Runs before the Detector so attached
  # transactions are excluded from re-detection.
  class Matcher
    extend T::Sig

    # A candidate charge must land within this fraction of the series average
    # to be considered at all; inside amount_band it's "paid", outside it's
    # "paid_amount_changed" (and may fire a price-change event).
    PLAUSIBLE_FRACTION = 0.6

    # Yodlee-style dual threshold for price-change events: both an absolute
    # and a relative jump, throttled to one event per 31 days per series.
    PRICE_CHANGE_MIN_ABS = 10.0
    PRICE_CHANGE_MIN_PCT = 0.10
    PRICE_CHANGE_THROTTLE = T.let(31.days, ActiveSupport::Duration)

    sig { void }
    def self.run
      new.run
    end

    sig { void }
    def run
      series_list = RecurringSeries.where(status: [ RecurringSeries::Status::Active, RecurringSeries::Status::Lapsed ]).to_a
      return if series_list.empty?

      # A transaction appears in the pool under both its merchant and its
      # description key; this guards against double-attachment within a run.
      @attached = T.let(Set.new, T.nilable(T::Set[String]))
      pool = build_pool(series_list)
      series_list.each { |series| match_series(series, pool) }
    end

    private

    # One query for all unattached candidate outflows, grouped for lookup by
    # merchant and by normalized description.
    sig { params(series_list: T::Array[RecurringSeries]).returns(T::Hash[String, T::Array[CashTransaction]]) }
    def build_pool(series_list)
      earliest = series_list.filter_map(&:last_charge_date).min || 1.year.ago.to_date
      txns = CashTransaction
        .where("cash_transactions.amount < 0")
        .where.not(transaction_type: "Payment")
        .where(
          "cash_transactions.transfer_id IS NULL OR " \
          "cash_transactions.transfer_id IN (SELECT id FROM transfers WHERE include_in_spend)"
        )
        .where("transaction_date > ?", earliest)
        .where.missing(:recurring_occurrence)

      pool = Hash.new { |h, k| h[k] = [] }
      txns.find_each do |t|
        pool["merchant:#{t.merchant_id}"] << t if t.merchant_id
        pool["desc:#{Normalizer.normalize(t.description)}"] << t
      end
      pool
    end

    sig { params(series: RecurringSeries, pool: T::Hash[String, T::Array[CashTransaction]]).void }
    def match_series(series, pool)
      key = series.merchant_id ? "merchant:#{series.merchant_id}" : "desc:#{series.description_pattern}"
      candidates = pool.fetch(key, []).sort_by(&:transaction_date)
      return if candidates.empty?

      tol = series.schedule.tolerance_days
      avg = series.average_amount.to_f

      candidates.each do |txn|
        next if T.must(@attached).include?(txn.id)

        amount = txn.amount.to_f.abs
        next if (amount - avg).abs > avg * PLAUSIBLE_FRACTION

        window = (txn.transaction_date - tol)..(txn.transaction_date + tol)
        occ = series.recurring_occurrences.pending.where(expected_date: window).chronological.first

        # A lapsed series has stopped scheduling; any plausible new charge
        # revives it at the charge's own date. "New" means after the last
        # charge: the pool reaches back to the oldest series' last charge, so
        # it also holds this series' own unattached history (a second charge
        # on a day already paid), which must not revive it. The charge's date
        # can still hold a missed or skipped row, which the charge then pays.
        occ ||= revival_occurrence(series, txn) if series.status == RecurringSeries::Status::Lapsed
        next unless occ

        attach(series, occ, txn)
      end
    end

    sig { params(series: RecurringSeries, txn: CashTransaction).returns(T.nilable(RecurringOccurrence)) }
    def revival_occurrence(series, txn)
      last_charge = series.last_charge_date
      return if last_charge && txn.transaction_date <= last_charge

      occ = series.recurring_occurrences.find_or_initialize_by(expected_date: txn.transaction_date)
      return if RecurringOccurrence::PAID_STATUSES.include?(occ.status)

      occ.expected_amount ||= series.average_amount
      occ
    end

    sig { params(series: RecurringSeries, occ: RecurringOccurrence, txn: CashTransaction).void }
    def attach(series, occ, txn)
      amount = txn.amount.to_f.abs.round(2).to_f
      within = series.amount_band.cover?(amount)
      occ.update!(
        status: within ? RecurringOccurrence::Status::Paid : RecurringOccurrence::Status::PaidAmountChanged,
        cash_transaction_id: txn.id,
        charged_date: txn.transaction_date,
        amount: amount
      )
      T.must(@attached) << txn.id
      check_price_change(series, amount) unless within
      series.transition_to!(RecurringSeries::Status::Active) if series.status == RecurringSeries::Status::Lapsed
      refresh_series(series, occ, amount)
    end

    sig { params(series: RecurringSeries, occ: RecurringOccurrence, amount: Float).void }
    def refresh_series(series, occ, amount)
      paid = series.recurring_occurrences.paid_like.order(:charged_date).last(6)
      trailing_avg = (paid.sum { |o| o.amount.to_f } / paid.size).round(2)
      next_expected = series.schedule.advance(occ.expected_date)
      next_expected = [ next_expected, series.next_expected_date ].compact.max

      series.update!(
        last_charge_date: [ occ.charged_date, series.last_charge_date ].compact.max,
        last_amount: amount,
        average_amount: trailing_avg,
        min_amount: [ series.min_amount&.to_f, amount ].compact.min,
        max_amount: [ series.max_amount&.to_f, amount ].compact.max,
        misses_streak: 0,
        next_expected_date: next_expected
      )
      series.recurring_occurrences.find_or_create_by!(expected_date: next_expected) do |o|
        o.status = RecurringOccurrence::Status::Upcoming
        o.expected_amount = BigDecimal(trailing_avg.to_s)
      end
    end

    sig { params(series: RecurringSeries, new_amount: Float).void }
    def check_price_change(series, new_amount)
      previous = series.last_amount.to_f
      return if previous.zero?

      delta = (new_amount - previous).abs
      return unless delta >= PRICE_CHANGE_MIN_ABS && delta >= previous * PRICE_CHANGE_MIN_PCT
      return if series.last_price_change_at && T.must(series.last_price_change_at) > PRICE_CHANGE_THROTTLE.ago

      series.update!(last_price_change_at: Time.current)
      Workflows::Events.publish("subscription.price_changed", subject: series, payload: {
        "previous_amount" => previous.round(2),
        "new_amount" => new_amount.round(2),
        "delta" => (new_amount - previous).round(2)
      })
    end
  end
end
