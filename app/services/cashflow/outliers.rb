# typed: strict

module Cashflow
  # Tukey-fence outlier detection over spend transactions. A transaction is
  # flagged when its amount clears Q3 + 1.5×IQR sized from a trailing
  # 12-month baseline — preferring its own category's fence when that
  # category has enough history (so a category with naturally large
  # transactions, like Rent, rarely trips it) and falling back to a
  # household-wide fence otherwise. That fallback is exactly the case that
  # matters most: a rare, large payment is almost always in a category too
  # sparse to size its own fence. Uncategorized transactions only ever get
  # the household-wide fence, for the same reason.
  #
  # The fence comparison runs in SQL (a VALUES join of the per-category
  # fences against the rows) and returns only the flagged rows — this used
  # to instantiate every spend transaction in the range as an AR object and
  # compare in Ruby, which on a no-param dashboard load meant materializing
  # the household's entire spend history per cache miss.
  class Outliers
    extend T::Sig

    BASELINE    = T.let(1.year, ActiveSupport::Duration)
    MIN_SAMPLES = 6
    MIN_EXCESS  = 100.0
    LIMIT       = 8

    PERCENTILES = [
      Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY ABS(cash_transactions.amount))"),
      Arel.sql("percentile_cont(0.25) WITHIN GROUP (ORDER BY ABS(cash_transactions.amount))"),
      Arel.sql("percentile_cont(0.75) WITHIN GROUP (ORDER BY ABS(cash_transactions.amount))")
    ].freeze

    sig { params(spend_scope: T.untyped).void }
    def initialize(spend_scope:)
      @spend_scope = T.let(spend_scope, T.untyped)
    end

    # Flagged rows within `range` as
    # {transaction_id, description, category_name, transaction_date, amount,
    # multiple}. `transaction_date` stays a Date (not stringified) so callers
    # can both group by month and filter by a narrower sub-range from the
    # same result.
    sig { params(range: T::Range[T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def flagged(range)
      baseline_range = (range.end - BASELINE)..range.end

      category_fences = @spend_scope
        .joins(:category)
        .where(transaction_date: baseline_range)
        .group("categories.id")
        .having("COUNT(*) >= ?", MIN_SAMPLES)
        .pluck(Arel.sql("categories.id"), *PERCENTILES)
        .each_with_object({}) do |(category_id, median, q1, q3), memo|
          memo[category_id] = tukey_stat(median, q1, q3)
        end

      household_scope = @spend_scope.where(transaction_date: baseline_range)
      household_stat =
        if household_scope.count >= MIN_SAMPLES
          median, q1, q3 = household_scope.pick(*PERCENTILES)
          tukey_stat(median, q1, q3)
        end
      return [] if category_fences.empty? && household_stat.nil?

      scope = @spend_scope
        .where(transaction_date: range)
        .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
        .joins("LEFT JOIN categories ON categories.id = cash_transactions.category_id")

      # Every value reaches SQL as a bind: the per-category fences as three
      # parallel arrays unnested into a join, the household-wide fallback as
      # :fence / :median.
      binds = { fence: household_stat&.fetch(:fence), median: household_stat&.fetch(:median), min_excess: MIN_EXCESS }
      if category_fences.any?
        scope = scope.joins(ActiveRecord::Base.sanitize_sql_array([
          "LEFT JOIN unnest(ARRAY[:ids]::uuid[], ARRAY[:medians]::float8[], ARRAY[:fences]::float8[]) " \
          "AS outlier_fences(category_id, median, fence) ON outlier_fences.category_id = cash_transactions.category_id",
          { ids: category_fences.keys,
            medians: category_fences.values.map { |stat| stat[:median] },
            fences: category_fences.values.map { |stat| stat[:fence] } }
        ]))
        fence_sql  = "COALESCE(outlier_fences.fence, CAST(:fence AS float8))"
        median_sql = "COALESCE(outlier_fences.median, CAST(:median AS float8))"
      else
        fence_sql  = "CAST(:fence AS float8)"
        median_sql = "CAST(:median AS float8)"
      end

      # amount >= fence && (amount - fence) >= MIN_EXCESS ⇔ the single
      # comparison below (fence and excess are both positive).
      scope
        .where("#{fence_sql} IS NOT NULL AND ABS(cash_transactions.amount) >= #{fence_sql} + :min_excess", binds)
        .pluck(
          Arel.sql("cash_transactions.id"),
          Arel.sql("COALESCE(merchants.name, cash_transactions.description)"),
          Arel.sql("COALESCE(categories.name, 'Uncategorized')"),
          Arel.sql("cash_transactions.transaction_date"),
          Arel.sql("ABS(cash_transactions.amount)"),
          Arel.sql(ActiveRecord::Base.sanitize_sql_array([ median_sql, binds ]))
        )
        .map do |id, description, category_name, date, amount, median|
          amount_f = amount.to_f
          median_f = median.to_f
          {
            transaction_id:   id,
            description:      description,
            category_name:    category_name,
            transaction_date: date,
            amount:           amount_f.round(2),
            multiple:         median_f.positive? ? (amount_f / median_f).round(1) : nil
          }
        end
    end

    # The dollar-biggest outliers within `range`, for the Outliers panel.
    sig { params(flagged: T::Array[T::Hash[Symbol, T.untyped]], range: T::Range[T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.top(flagged, range)
      flagged
        .select { |row| range.cover?(row[:transaction_date]) }
        .sort_by { |row| -row[:amount] }
        .first(LIMIT)
        .map { |row| row.merge(transaction_date: row[:transaction_date].to_s) }
    end

    # Total flagged-outlier dollars within `range` — how much a "common"
    # total should be reduced from its as-it-happened counterpart.
    sig { params(flagged: T::Array[T::Hash[Symbol, T.untyped]], range: T::Range[T.untyped]).returns(Float) }
    def self.sum_in(flagged, range)
      flagged.sum(0.0) { |row| range.cover?(row[:transaction_date]) ? row[:amount] : 0.0 }
    end

    # Monthly total minus that month's flagged-outlier amounts — the
    # "Common" line on the Monthly Spend chart. Grouped by
    # `beginning_of_month.to_s` to match groupdate's month keys exactly
    # ("YYYY-MM-01" — a mismatch here would silently subtract nothing).
    sig { params(flagged: T::Array[T::Hash[Symbol, T.untyped]], monthly_spend: T::Hash[String, Float]).returns(T::Hash[String, Float]) }
    def self.monthly_common(flagged, monthly_spend)
      outlier_by_month = flagged
        .group_by { |row| row[:transaction_date].beginning_of_month.to_s }
        .transform_values { |rows| rows.sum { |row| row[:amount] } }

      monthly_spend.each_with_object({}) do |(month, total), out|
        out[month] = (total - outlier_by_month.fetch(month, 0.0)).round(2)
      end
    end

    private

    sig { params(median: T.untyped, q1: T.untyped, q3: T.untyped).returns(T::Hash[Symbol, Float]) }
    def tukey_stat(median, q1, q3)
      { median: median.to_f, fence: q3.to_f + 1.5 * (q3.to_f - q1.to_f) }
    end
  end
end
