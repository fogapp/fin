# typed: strict

module Recurring
  # Turns transaction history into suggested RecurringSeries rows. Runs for
  # Current.household. Groups outflows by merchant (falling back to
  # normalized description), sub-splits noisy groups by amount cluster, runs
  # CadenceDetector per group, and upserts series keyed by series_key.
  #
  # User decisions are durable: dismissed and active/lapsed series are never
  # touched here (the Matcher maintains accepted series); only suggested
  # rows are refreshed in place. An ended series whose merchant starts
  # charging again is re-suggested on the same row, preserving history.
  class Detector
    extend T::Sig

    # Amount CV at or below this = fixed-price subscription; above = variable
    # bill with a widened matching tolerance; above MAX_BILL_CV the group is
    # split into per-price-point clusters instead.
    SUBSCRIPTION_CV = 0.075
    MAX_BILL_CV     = 0.35
    # Amounts further than this from the group median are outliers (refunds,
    # promo months) and are excluded rather than disqualifying the group.
    OUTLIER_FRACTION = 0.5
    # Detection only needs enough history to establish a cadence; loading
    # every outflow ever (as full AR objects, after every sync + nightly)
    # scaled with account age for no detection benefit. Anything older than
    # this either already produced a series or is a dead stream.
    LOOKBACK_MONTHS = 30

    class Stats < T::Struct
      prop :created, Integer, default: 0
      prop :refreshed, Integer, default: 0
      prop :failed, Integer, default: 0
    end

    sig { returns(Stats) }
    def self.run
      new.run
    end

    sig { returns(Stats) }
    def run
      stats = Stats.new
      groups.each do |key, txns|
        clusters = amount_clusters(txns)
        clusters.each do |cluster|
          # Per cluster: this runs nightly over every recurring stream in the
          # household, and one malformed group (a cadence that won't resolve, a
          # series that fails validation) used to abort the whole pass — so a
          # single bad stream silently stopped subscription detection for all
          # the others until someone noticed.
          emit(key, cluster, stats, split: clusters.size > 1)
        rescue => e
          stats.failed += 1
          Rails.logger.warn("[Recurring::Detector] group #{key} failed: #{e.class}: #{e.message}")
          Activity.record(
            source:   "recurring",
            event:    "recurring.group_failed",
            severity: Severity::Warning,
            summary:  "Recurring detection skipped #{key}: #{e.class}: #{e.message}",
            payload:  { group: key, error: e.class.name }
          )
        end
      end
      stats
    end

    private

    # Grouping is household-wide (not per-account) so a subscription that
    # moves between cards keeps one continuous stream. Transactions already
    # attached to a reviewed series (active/lapsed/ended/dismissed) are
    # excluded — their streams are settled; suggested series' evidence stays
    # in the pool so their groups can be re-derived with new data.
    sig { returns(T::Hash[String, T::Array[CashTransaction]]) }
    def groups
      attached = RecurringOccurrence
        .joins(:recurring_series)
        .where.not(recurring_series: { status: RecurringSeries::Status::Suggested })
        .where.not(cash_transaction_id: nil)
        .select(:cash_transaction_id)

      # Linked transfer legs (CC payments, account moves) follow the same
      # structural rule as spend_like: excluded unless the transfer opts into
      # spend (untracked-card proxies, budgetable loan payments).
      scope = CashTransaction
        .where("cash_transactions.amount < 0")
        .where("cash_transactions.transaction_date >= ?", Date.current - LOOKBACK_MONTHS.months)
        .where.not(transaction_type: "Payment")
        .where(
          "cash_transactions.transfer_id IS NULL OR " \
          "cash_transactions.transfer_id IN (SELECT id FROM transfers WHERE include_in_spend)"
        )
        .where.not(id: attached)
        .order(:transaction_date)
        .select(:id, :merchant_id, :description, :amount, :transaction_date)
        .includes(:merchant)

      scope.group_by { |t| t.merchant_id ? "merchant:#{t.merchant_id}" : "desc:#{Normalizer.normalize(t.description)}" }
           .select { |_key, txns| txns.size >= 2 }
    end

    # One cluster for coherent groups; per-price-point clusters (>= 3 txns
    # each) when amounts are too scattered to be a single stream.
    sig { params(txns: T::Array[CashTransaction]).returns(T::Array[T::Array[CashTransaction]]) }
    def amount_clusters(txns)
      # Coherent group: one stream, minus outliers (refunds, promo months).
      # Scattered group (bimodal prices or a wild outlier): greedy
      # per-price-point clustering, keeping clusters big enough to verify.
      if coefficient_of_variation(txns) <= MAX_BILL_CV
        med = median(txns.map { |t| t.amount.to_f.abs })
        kept = txns.select { |t| (t.amount.to_f.abs - med).abs <= med * OUTLIER_FRACTION }
        return kept.size >= 2 ? [ kept ] : []
      end

      clusters = T.let([], T::Array[T::Array[CashTransaction]])
      txns.sort_by { |t| t.amount.to_f.abs }.each do |t|
        current = clusters.last
        if current && (t.amount.to_f.abs - cluster_mean(current)).abs <= cluster_mean(current) * 0.1
          current << t
        else
          clusters << [ t ]
        end
      end
      clusters.select { |c| c.size >= CadenceDetector::MIN_HITS }
    end

    sig { params(key: String, txns: T::Array[CashTransaction], stats: Stats, split: T::Boolean).void }
    def emit(key, txns, stats, split:)
      # T.must inside transform_values, not `&:first`: group_by never yields an
      # empty group so the head is always there, but Array#first types as
      # nilable and rebuild_occurrences takes a non-nilable value hash.
      by_date = txns.group_by(&:transaction_date).transform_values { |group| T.must(group.first) }
      result = CadenceDetector.detect(by_date.keys)
      return unless result

      matched_txns = result.matches.values.map { |d| T.must(by_date[d]) }
      last_charge = T.must(result.matches.values.max)
      schedule = result.schedule

      # Dead streams (already 2+ periods stale) aren't worth reviewing; if
      # they matter they'll show up via an ended/lapsed series instead.
      return if Date.current > schedule.advance(schedule.advance(last_charge)) + schedule.tolerance_days

      series_key = split ? "#{key}:amt#{cluster_mean(txns).round}" : key
      series = RecurringSeries.find_or_initialize_by(series_key: series_key)

      case series.status
      when RecurringSeries::Status::Dismissed, RecurringSeries::Status::Active, RecurringSeries::Status::Lapsed then return
      when RecurringSeries::Status::Ended
        return unless series.ended_at && last_charge > T.must(series.ended_at).to_date

        series.transition_to!(RecurringSeries::Status::Suggested)
      end

      apply_attributes(series, key, txns, matched_txns, result)
      was_new = series.new_record?
      series.save!
      rebuild_occurrences(series, by_date, result)

      if was_new
        stats.created += 1
        Workflows::Events.publish("subscription.suggested", subject: series)
      else
        stats.refreshed += 1
      end
    end

    sig do
      params(series: RecurringSeries, key: String, txns: T::Array[CashTransaction],
             matched: T::Array[CashTransaction], result: CadenceDetector::Result).void
    end
    def apply_attributes(series, key, txns, matched, result)
      amounts = matched.map { |t| t.amount.to_d.abs }
      cv = coefficient_of_variation(matched)
      first_txn = T.must(matched.min_by(&:transaction_date))
      last_date = T.must(matched.map(&:transaction_date).max)

      series.assign_attributes(
        source: series.source,
        merchant_id: first_txn.merchant_id,
        description_pattern: key.start_with?("desc:") ? key.delete_prefix("desc:") : nil,
        name: series.name.presence || first_txn.merchant&.name || key.delete_prefix("desc:").titleize,
        kind: cv <= SUBSCRIPTION_CV ? RecurringSeries::Kind::Subscription : RecurringSeries::Kind::Bill,
        amount_tolerance: (1.5 * cv).clamp(SUBSCRIPTION_CV, MAX_BILL_CV),
        granularity: result.schedule.granularity,
        quantity: result.schedule.quantity,
        anchor: result.schedule.anchor,
        average_amount: (amounts.sum / amounts.size).round(2),
        last_amount: T.must(matched.max_by(&:transaction_date)).amount.to_d.abs.round(2),
        min_amount: T.must(amounts.min).round(2),
        max_amount: T.must(amounts.max).round(2),
        confidence: result.confidence,
        first_charge_date: first_txn.transaction_date,
        last_charge_date: last_date,
        next_expected_date: result.schedule.advance(last_date)
      )
    end

    # Suggested-series evidence is fully re-derived each run: paid rows for
    # matched history, missed rows for interior gaps, one pending row for the
    # next expected charge.
    sig { params(series: RecurringSeries, by_date: T::Hash[Date, CashTransaction], result: CadenceDetector::Result).void }
    def rebuild_occurrences(series, by_date, result)
      # Transactional: a mid-rebuild failure must not leave the series with
      # its old evidence destroyed but the new rows only partially created.
      RecurringOccurrence.transaction do
        new_txn_ids = result.matches.values.map { |d| T.must(by_date[d]).id }
        # Re-derive everything except paid history from other transactions — a
        # re-suggested ended series keeps its pre-cancellation evidence.
        series.recurring_occurrences.where.not(status: RecurringOccurrence::PAID_STATUSES).destroy_all
        series.recurring_occurrences.where(cash_transaction_id: new_txn_ids).destroy_all

        avg = series.average_amount
        taken = series.recurring_occurrences.pluck(:expected_date).to_set

        result.matches.each do |expected, actual|
          next if taken.include?(expected)

          txn = T.must(by_date[actual])
          series.recurring_occurrences.create!(
            expected_date: expected, status: RecurringOccurrence::Status::Paid, cash_transaction_id: txn.id,
            charged_date: actual, amount: txn.amount.to_d.abs.round(2), expected_amount: avg
          )
        end
        result.missed_dates.each do |date|
          next if taken.include?(date)

          series.recurring_occurrences.create!(expected_date: date, status: RecurringOccurrence::Status::Missed, expected_amount: avg)
        end
        next_date = T.must(series.next_expected_date)
        series.recurring_occurrences.create!(expected_date: next_date, status: RecurringOccurrence::Status::Upcoming, expected_amount: avg) unless taken.include?(next_date)
      end
    end

    sig { params(txns: T::Array[CashTransaction]).returns(Float) }
    def coefficient_of_variation(txns)
      amounts = txns.map { |t| t.amount.to_f.abs }
      mean = amounts.sum / amounts.size
      return 0.0 if mean.zero?

      variance = amounts.sum { |a| (a - mean)**2 } / amounts.size
      Math.sqrt(variance) / mean
    end

    sig { params(txns: T::Array[CashTransaction]).returns(Float) }
    def cluster_mean(txns)
      txns.sum(0.0) { |t| t.amount.to_f.abs } / txns.size
    end

    sig { params(values: T::Array[Float]).returns(Float) }
    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      (sorted.size.odd? ? T.must(sorted[mid]) : (T.must(sorted[mid - 1]) + T.must(sorted[mid])) / 2.0).to_f
    end
  end
end
