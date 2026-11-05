# typed: strict
# frozen_string_literal: true

module CashTransactions
  # Everything the transaction page needs to explain one row against the rest
  # of the household's money, in one request:
  #
  #   - history:    the row's peers (same merchant, else a near-identical
  #                 descriptor) — the strip chart's dots and the "is this
  #                 normal?" statistics over them;
  #   - cadence:    whether those peers recur on a schedule, inferred by the
  #                 same Recurring::CadenceDetector subscription detection
  #                 uses, so "this looks monthly" here and a suggested series
  #                 on the subscriptions page are the same judgment;
  #   - series:     the subscription this row belongs to (or the one tracking
  #                 its merchant);
  #   - treatment:  whether it counts as spend / income / budget, from the
  #                 authoritative scopes rather than a client-side re-derivation;
  #   - budget:     the budget line it lands on that month and what it did to it;
  #   - duplicates, related (refunds / the charge a refund reverses) and the
  #     rest of the same day's activity.
  class Context
    extend T::Sig

    # Peers rendered as dots. Totals and statistics cover every peer.
    HISTORY_LIMIT = 240
    # Trigram similarity for description peers — the #similar endpoint's bar.
    SIMILARITY_THRESHOLD = 0.45
    # A peer counts toward cadence when its amount is this close to the row's
    # (a $15.99 plan that became $17.99 still reads as one stream).
    CADENCE_AMOUNT_BAND = 0.35
    DUPLICATE_WINDOW_DAYS = 2
    RELATED_WINDOW_DAYS = 90
    SAME_DAY_LIMIT = 12
    RELATED_LIMIT = 5
    BUDGET_HISTORY_MONTHS = 6

    sig { params(transaction: ::CashTransaction).void }
    def initialize(transaction)
      @t = transaction
      @peers = T.let(nil, T.nilable(T::Array[::CashTransaction]))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      spend = ::CashTransaction.spend_like.exists?(id: @t.id)
      {
        history:            history,
        stats:              stats,
        cadence:            cadence,
        series:             series,
        treatment:          {
          spend:             spend,
          income:            ::CashTransaction.income_like.exists?(id: @t.id),
          budget:            spend && !@t.budget_excluded,
          merchant_excluded: @t.merchant&.excluded || false
        },
        budget:             spend && !@t.budget_excluded ? budget : nil,
        duplicates:         duplicates,
        related:            related,
        same_day:           same_day,
        suggested_category: suggested_category
      }
    end

    # Rows sharing a descriptor with `source`, by trigram similarity. Shared
    # with the #similar endpoint so the two can't disagree on what "similar"
    # means.
    sig { params(source: ::CashTransaction, query: String).returns(ActiveRecord::Relation) }
    def self.similar_scope(source, query)
      ::CashTransaction
        .where.not(id: source.id)
        .where(
          "cash_transactions.description % :query AND " \
          "similarity(cash_transactions.description, :query) >= :threshold",
          query: query, threshold: SIMILARITY_THRESHOLD
        )
    end

    private

    sig { returns(String) }
    def basis
      return "merchant" if @t.merchant_id
      return "description" if @t.description.to_s.strip.present?

      "none"
    end

    # Peers on the same side of the ledger (charges with charges, credits with
    # credits), including the row itself, oldest first.
    sig { returns(T::Array[::CashTransaction]) }
    def peers
      @peers ||= begin
        scope = case basis
        when "merchant"    then ::CashTransaction.where(merchant_id: @t.merchant_id)
        when "description" then ::CashTransaction.where(id: self.class.similar_scope(@t, @t.description.to_s.strip).select(:id)).or(::CashTransaction.where(id: @t.id))
        else ::CashTransaction.where(id: @t.id)
        end
        scope = @t.amount.negative? ? scope.where("amount < 0") : scope.where("amount >= 0")
        scope.includes(:account, :category, :merchant).order(:transaction_date, :id).to_a
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def history
      shown = peers.last(HISTORY_LIMIT)
      # The row itself is always plotted, even when it is older than the window.
      shown = [ @t ] + shown unless shown.any? { |p| p.id == @t.id }
      {
        basis: basis,
        label: basis == "merchant" ? @t.merchant&.name : Recurring::Normalizer.normalize(@t.description).presence,
        total: peers.size,
        rows:  shown.map { |p| row(p) }
      }
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def stats
      return nil if peers.size < 2

      amounts = peers.map { |p| p.amount.to_f.abs }.sort
      this = @t.amount.to_f.abs
      median = quantile(amounts, 0.5)
      year_ago = @t.transaction_date - 1.year
      trailing = peers.select { |p| p.transaction_date > year_ago && p.transaction_date <= @t.transaction_date }
      {
        count:               peers.size,
        ordinal:             peers.index { |p| p.id == @t.id }.to_i + 1,
        median:              median.round(2),
        p25:                 quantile(amounts, 0.25).round(2),
        p75:                 quantile(amounts, 0.75).round(2),
        min:                 T.must(amounts.first).round(2),
        max:                 T.must(amounts.last).round(2),
        # Share of peers at or below this amount, 0..1.
        percentile:          (amounts.count { |a| a <= this }.to_f / amounts.size).round(3),
        ratio_to_median:     median.positive? ? (this / median).round(2) : nil,
        first_date:          T.must(peers.first).transaction_date,
        last_date:           T.must(peers.last).transaction_date,
        trailing_year_total: trailing.sum { |p| p.amount.to_f.abs }.round(2),
        trailing_year_count: trailing.size
      }
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def cadence
      this = @t.amount.to_f.abs
      return nil if this.zero?

      band = peers.select { |p| ((p.amount.to_f.abs - this).abs / this) <= CADENCE_AMOUNT_BAND }
      by_date = T.let(band.index_by(&:transaction_date), T::Hash[Date, ::CashTransaction])
      result = Recurring::CadenceDetector.detect(by_date.keys)
      return nil unless result

      matched = result.matches.values.sort
      schedule = result.schedule
      {
        granularity:        schedule.granularity.serialize,
        quantity:           schedule.quantity,
        anchor:             schedule.anchor,
        description:        schedule.description,
        confidence:         result.confidence,
        hit_rate:           result.hit_rate,
        matched_count:      matched.size,
        missed_count:       result.missed_dates.size,
        includes_transaction: matched.include?(@t.transaction_date),
        average_amount:     (matched.sum { |d| T.must(by_date[d]).amount.to_f.abs } / matched.size).round(2),
        next_expected_date: schedule.advance(T.must(matched.last)),
        matched_ids:        matched.map { |d| T.must(by_date[d]).id }
      }
    end

    # The series this row was charged against, else one tracking its merchant
    # (live statuses first, so an active subscription beats a dismissed guess).
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def series
      own = @t.recurring_series
      found = own || (@t.merchant_id && RecurringSeries.where(merchant_id: @t.merchant_id)
        .order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'suggested' THEN 1 WHEN 'lapsed' THEN 2 ELSE 3 END"), updated_at: :desc)
        .first)
      return nil unless found

      {
        id:                   found.id,
        name:                 found.name,
        status:               found.status.serialize,
        kind:                 found.kind.serialize,
        cadence_description:  found.cadence_description,
        next_expected_date:   found.next_expected_date,
        average_amount:       found.average_amount.to_f,
        annual_equivalent:    (found.average_amount.to_f * found.schedule.periods_per_year).round(2),
        includes_transaction: !own.nil?
      }
    end

    # The budget line the row's spend lands on that month — its category's
    # own line, else the parent's line it rolls into, else "everything else".
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def budget
      month = @t.transaction_date.beginning_of_month
      return nil if month > Date.current.beginning_of_month

      contribution = -@t.amount.to_f
      book = Budgets::Month.new(month: month)
      plan = Budgets::Plan.new(through: month)
      category = @t.category
      parent_id = category&.parent_id
      line = category && (plan.line_for(category.id, month) || (parent_id && plan.line_for(parent_id, month)))

      if line
        payload = book.line_payload(line)
        available = (payload[:planned] + payload[:rollover_amount]).round(2)
        {
          scope:         "line",
          category_id:   payload[:category_id],
          category_name: payload[:category_name],
          period:        payload[:period],
          month:         month.strftime("%Y-%m"),
          available:     available,
          actual:        payload[:actual],
          before:        (payload[:actual] - contribution).round(2),
          contribution:  contribution.round(2),
          remaining:     payload[:remaining],
          typical:       payload[:typical],
          history:       book.line_history(line.category_id, months: BUDGET_HISTORY_MONTHS)
        }
      else
        other = book.call[:everything_else]
        {
          scope:         "everything_else",
          category_id:   nil,
          category_name: nil,
          period:        "monthly",
          month:         month.strftime("%Y-%m"),
          available:     other[:planned],
          actual:        other[:actual],
          before:        (other[:actual] - contribution).round(2),
          contribution:  contribution.round(2),
          remaining:     other[:remaining],
          typical:       nil,
          history:       []
        }
      end
    end

    # Same account, same amount, a day or two apart, and the same descriptor
    # once reference numbers are stripped — the shape of a double-posted
    # charge. Merchant alone isn't enough: two $6 coffees at one café three
    # days apart are just a habit.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def duplicates
      key = Recurring::Normalizer.normalize(@t.description)
      return [] if key.blank?

      window = (@t.transaction_date - DUPLICATE_WINDOW_DAYS)..(@t.transaction_date + DUPLICATE_WINDOW_DAYS)
      ::CashTransaction.where(account_id: @t.account_id, amount: @t.amount, transaction_date: window)
        .where.not(id: @t.id)
        .where(transfer_id: nil)
        .includes(:account, :category, :merchant)
        .order(:transaction_date)
        .select { |d| Recurring::Normalizer.normalize(d.description) == key }
        .first(RELATED_LIMIT)
        .map { |d| row(d).merge(date_diff: (d.transaction_date - @t.transaction_date).to_i) }
    end

    # Money the other way at the same merchant nearby: the refund for a
    # charge, or the charge a refund reverses.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def related
      return [] unless @t.merchant_id

      window = (@t.transaction_date - RELATED_WINDOW_DAYS)..(@t.transaction_date + RELATED_WINDOW_DAYS)
      scope = ::CashTransaction.where(merchant_id: @t.merchant_id, transaction_date: window).where.not(id: @t.id)
      scope = @t.amount.negative? ? scope.where("amount > 0") : scope.where("amount < 0")
      scope.includes(:account, :category, :merchant)
        .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([
          "ABS(ABS(cash_transactions.amount) - ?) ASC, ABS(cash_transactions.transaction_date - DATE ?) ASC",
          @t.amount.abs, @t.transaction_date
        ])))
        .limit(RELATED_LIMIT)
        .map { |r| row(r).merge(date_diff: (r.transaction_date - @t.transaction_date).to_i) }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def same_day
      scope = ::CashTransaction.where(transaction_date: @t.transaction_date).where.not(id: @t.id)
      rows = scope.includes(:account, :category, :merchant)
        .order(Arel.sql("ABS(cash_transactions.amount) DESC"), :id)
        .limit(SAME_DAY_LIMIT)
        .map { |r| row(r) }
      { total: scope.count, rows: rows }
    end

    # The category the row's peers most often carry, when it isn't the row's
    # own — "11 of 12 Starbucks charges are Coffee".
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def suggested_category
      others = peers.reject { |p| p.id == @t.id }
      categorized = others.select(&:category_id)
      return nil if categorized.empty?

      category_id, count = categorized.map(&:category_id).tally.max_by { |_, c| c }
      return nil if category_id.nil? || category_id == @t.category_id

      category = T.must(categorized.find { |p| p.category_id == category_id }).category
      { category_id: category_id, category_name: category&.name, count: count, of: others.size }
    end

    sig { params(r: ::CashTransaction).returns(T::Hash[Symbol, T.untyped]) }
    def row(r)
      {
        id:               r.id,
        transaction_date: r.transaction_date,
        description:      r.description,
        amount:           r.amount.to_f,
        account_name:     r.account&.name,
        merchant_name:    r.merchant&.name,
        category_id:      r.category_id,
        category_name:    r.category&.name,
        transfer_id:      r.transfer_id
      }
    end

    # Linear-interpolated quantile of a sorted array.
    sig { params(sorted: T::Array[Float], q: Float).returns(Float) }
    def quantile(sorted, q)
      pos = (sorted.size - 1) * q
      lower = T.must(sorted[pos.floor])
      upper = T.must(sorted[pos.ceil])
      lower + ((upper - lower) * (pos - pos.floor))
    end
  end
end
