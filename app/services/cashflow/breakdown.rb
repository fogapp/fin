# typed: strict

module Cashflow
  # Ranked and per-month spend aggregation shared by the cashflow endpoints
  # (and by category/tag detail pages via /cashflow/spend_breakdown).
  class Breakdown
    extend T::Sig

    # How many entities get their own band in a stacked breakdown before the
    # tail folds into "other". Matches ranked_totals' limit so the chart's
    # series and the By Category / By Merchant panels name the same set —
    # that's what lets the page share one entity→color assignment between
    # them.
    LIMIT     = 8
    OTHER_KEY = "other"

    # One month × entity grid: the top LIMIT entities by window total, each
    # with its own monthly amounts, plus an "other" remainder so every
    # month's stack sums to `monthly_total` — the same number the Total line
    # shows, which keeps the y-scale (and the share-of-total mode) honest
    # across a mode switch. The remainder is derived by subtraction rather
    # than by summing the tail precisely because it also has to absorb spend
    # the scope can't see at all: uncategorized rows for the category split,
    # merchant-less rows for the merchant one.
    #
    # Amounts are negated, not abs'd — a refund nets out of its own month
    # instead of inflating it, and that's also what makes the subtraction
    # balance.
    sig do
      params(scope: T.untyped, id_expr: String, name_expr: String, monthly_total: T::Hash[String, Float], limit: Integer)
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.monthly(scope, id_expr:, name_expr:, monthly_total:, limit: LIMIT)
      # Grouped with explicit SQL rather than group_by_period so the
      # composite key's element order is the group clause order, not
      # groupdate's.
      rows = scope
        .group(Arel.sql(id_expr), Arel.sql(name_expr))
        .group(Arel.sql("DATE_TRUNC('month', cash_transactions.transaction_date)::date"))
        .sum(:amount)
        .map { |(id, name, month), amount| [ id.to_s, name.to_s, month.to_s, -amount.to_f ] }

      names  = rows.each_with_object({}) { |(id, name, _, _), memo| memo[id] = name }
      totals = rows.each_with_object(Hash.new(0.0)) { |(id, _, _, amount), memo| memo[id] += amount }
      # Name breaks ties so two equal-spend entities can't swap slots (and
      # therefore colors) between requests.
      top = totals.sort_by { |id, total| [ -total, names[id] ] }.first(limit).map(&:first)

      months = T.let({}, T::Hash[String, T::Hash[String, Float]])
      rows.each do |id, _name, month, amount|
        next unless top.include?(id)
        bucket = (months[month] ||= {})
        bucket[id] = (bucket.fetch(id, 0.0) + amount).round(2).to_f
      end

      monthly_total.each do |month, total|
        bucket = (months[month] ||= {})
        rest = (total - bucket.values.sum).round(2).to_f
        bucket[OTHER_KEY] = rest if rest.abs >= 0.01
      end

      series = top.map { |id| { id: id, name: names[id] } }
      series << { id: OTHER_KEY, name: "Other" } if months.any? { |_, values| values.key?(OTHER_KEY) }

      { series: series, months: months }
    end

    # Ranked category/merchant totals for the By Category / By Merchant
    # panels: amount (for ranking and the bar fill), avg_monthly (amount
    # spread over the window's month count, not a monthly breakdown — the
    # panels show a snapshot total, not a time series), and largest (the
    # single biggest transaction), so each row can explain itself without a
    # drill-down. Like the monthly breakdown, amounts are negated rather
    # than abs'd so a return nets out of its category/merchant instead of
    # adding to it; a row that nets to zero or a refund drops off the list.
    sig { params(scope: T.untyped, id_expr: String, name_expr: String, months: Integer, limit: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.ranked(scope, id_expr:, name_expr:, months:, limit: LIMIT)
      scope
        .group(Arel.sql(id_expr), Arel.sql(name_expr))
        .pluck(
          Arel.sql(id_expr), Arel.sql(name_expr),
          Arel.sql("-SUM(cash_transactions.amount)"),
          Arel.sql("-MIN(cash_transactions.amount)")
        )
        .select { |_, _, total, _| total.to_f.positive? }
        .map do |id, name, total, largest|
          total_f = total.to_f
          { id: id, name: name, amount: total_f.round(2), avg_monthly: (total_f / months).round(2), largest: largest.to_f.round(2) }
        end
        .sort_by { |row| -row[:amount] }
        .first(limit)
    end
  end
end
