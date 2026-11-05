# typed: strict

module Budgets
  # The full budget picture for one month, from the standing plan (see
  # Budgets::Plan): monthly lines with rollover chains, yearly lines measured
  # year-to-date, the "everything else" line for spend outside budgeted
  # categories, the zero-based left-to-plan summary, pace, and — for the
  # current month — an end-of-month forecast.
  #
  # Actuals follow the cashflow convention (credit-card sales = spend,
  # income_like = income), minus transactions excluded from budgets. A
  # line's actual includes its subcategories' spend unless a subcategory has
  # its own line for the month.
  #
  # All aggregates come from a handful of window-wide queries memoized per
  # instance — the plan, income grouped by month, and a Budgets::SpendRollup
  # (spend grouped by month × category plus the category tree) — instead of
  # per-line per-month scans.
  class Month
    extend T::Sig

    ROLLOVER_LOOKBACK_MONTHS = 12
    APPROACHING_THRESHOLD = 0.9
    # Months of history behind a category's "typical" spend (the median).
    TYPICAL_MONTHS = 6

    sig { params(month: Date).void }
    def initialize(month: Date.current)
      @month = T.let(month.beginning_of_month, Date)
      @income_by_month = T.let(nil, T.nilable(T::Hash[Date, T.untyped]))
      @plan = T.let(nil, T.nilable(Plan))
      @rollup = T.let(nil, T.nilable(SpendRollup))
      @charges = T.let(nil, T.nilable(RecurringCharges))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      yearly, monthly = plan.lines_for(@month).partition(&:yearly?)
      monthly_rows = monthly.map { |line| line_payload(line) }.sort_by { |l| -l[:planned] }
      yearly_rows  = yearly.map { |line| line_payload(line) }.sort_by { |l| -l[:planned] }

      other = everything_else
      other_planned = other[:planned]
      forecast = forecast(monthly_rows, other)

      planned_total = (monthly_rows.sum { |l| l[:planned] } + (other_planned || 0)).round(2)
      actual_total  = (monthly_rows.sum { |l| l[:actual] } + (other_planned ? other[:actual] : 0)).round(2)
      remaining     = (monthly_rows.sum { |l| l[:remaining] } + (other[:remaining] || 0)).round(2)
      set_aside     = (yearly_rows.sum { |l| l[:planned] } / 12.0).round(2)
      income_planned = period_value(:income_planned)

      {
        month:         @month.strftime("%Y-%m"),
        income:        { planned: income_planned, actual: income_actual_for(@month), suggestion: income_suggestion },
        planned:       planned_total,
        actual:        actual_total,
        remaining:     remaining,
        left_to_plan:  income_planned ? (income_planned - planned_total - set_aside).round(2) : nil,
        lines:         monthly_rows,
        yearly:        {
          planned:   yearly_rows.sum { |l| l[:planned] }.round(2),
          actual:    yearly_rows.sum { |l| l[:actual] }.round(2),
          remaining: yearly_rows.sum { |l| l[:remaining] }.round(2),
          set_aside: set_aside,
          lines:     yearly_rows
        },
        everything_else: other,
        pace:          pace,
        forecast:      forecast
      }
    end

    # Payload for one line — also used by the threshold checker and the
    # line endpoint. A yearly line's actual is the calendar year to date.
    sig { params(line: BudgetLine).returns(T::Hash[Symbol, T.untyped]) }
    def line_payload(line)
      month_actual = rollup.spend(line.category_id, @month)
      actual = line.yearly? ? year_to_date(line.category_id) : month_actual
      rollover_amount = line.rollover && !line.yearly? ? rollover_for(line) : 0.0
      available = (rollover_amount + line.planned.to_f).round(2)
      category = T.must(line.category)
      {
        id:                 line.id,
        category_id:        line.category_id,
        category_name:      category.name,
        parent_id:          category.parent_id,
        parent_name:        category.parent&.name,
        period:             line.period,
        mode:               line.mode,
        set_in:             line.month.strftime("%Y-%m"),
        planned:            line.planned.to_f,
        rollover:           line.rollover,
        rollover_amount:    rollover_amount.round(2),
        actual:             actual,
        month_actual:       month_actual,
        remaining:          (available - actual).round(2),
        percent_used:       available.positive? ? ((actual / available) * 100).round(1) : (actual.positive? ? 100.0 : 0.0),
        typical:            line.yearly? ? trailing_year(line.category_id) : typical(line.category_id),
        projected:          nil,
        rolled_up_children: rolled_up_children_for(line)
      }
    end

    # Planned vs actual for one category over the trailing months (oldest
    # first, ending at the target month), by the plan in force each month.
    # A yearly plan shows as its monthly share.
    sig { params(category_id: String, months: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def line_history(category_id, months: 6)
      span = months.clamp(1, ROLLOVER_LOOKBACK_MONTHS)
      (0...span).map { |i| @month.months_ago(i) }.reverse.map do |m|
        line = plan.line_for(category_id, m)
        planned = line ? line.planned.to_f : 0.0
        {
          month:   m.strftime("%Y-%m"),
          planned: line&.yearly? ? (planned / 12).round(2) : planned,
          actual:  rollup.spend(category_id, m)
        }
      end
    end

    private

    sig { params(category_id: String).returns(Float) }
    def year_to_date(category_id)
      (1..@month.month).sum { |m| rollup.spend(category_id, Date.new(@month.year, m, 1)) }.round(2)
    end

    # Median monthly spend over the trailing months — robust to a one-off
    # purchase in a way an average isn't.
    sig { params(category_id: String).returns(Float) }
    def typical(category_id)
      Stats.median(rollup.history_months(@month, TYPICAL_MONTHS).map { |m| rollup.spend(category_id, m) }).round(2).to_f
    end

    sig { params(category_id: String).returns(Float) }
    def trailing_year(category_id)
      (1..12).sum { |i| rollup.spend(category_id, @month.months_ago(i)) }.round(2)
    end

    # Unbudgeted children (no line of their own this month) whose spend is
    # rolling into this line's actual — surfaced so the UI can show what's
    # being included rather than leaving the parent's total unexplained.
    sig { params(line: BudgetLine).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def rolled_up_children_for(line)
      budgeted_ids = rollup.budgeted_ids(@month)
      children = rollup.children_of(line.category_id).reject { |id| budgeted_ids.include?(id) }
      children.filter_map do |id|
        spend = rollup.spend_including_all_children(id, @month)
        next if spend.zero?

        { category_id: id, name: T.must(rollup.category(id)).first, actual: spend }
      end
    end

    # rollover(prev) + planned(prev) - actual(prev), chained back while the
    # plan in force kept rollover on (bounded lookback).
    sig { params(line: BudgetLine).returns(Float) }
    def rollover_for(line)
      carried = 0.0
      month = @month
      ROLLOVER_LOOKBACK_MONTHS.times do
        month = month.prev_month
        prev = plan.line_for(line.category_id, month)
        break if prev.nil? || !prev.rollover || prev.yearly?

        carried += prev.planned.to_f - rollup.spend(prev.category_id, month)
      end
      carried.round(2).to_f
    end

    # Spend outside every budgeted category (including uncategorized), with
    # the household's optional catch-all amount for it.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def everything_else
      planned = period_value(:other_planned)
      actual = unbudgeted_sums(@month).values.sum.to_f.abs.round(2)
      {
        planned:       planned,
        actual:        actual,
        uncategorized: (rollup.sums(@month)[nil] || 0).to_f.abs.round(2),
        remaining:     planned ? (planned - actual).round(2) : nil,
        projected:     nil
      }
    end

    # { category_id (or nil) => amount } for spend not covered by a line.
    sig { params(month: Date).returns(T::Hash[T.nilable(String), T.untyped]) }
    def unbudgeted_sums(month)
      covered = rollup.budgeted_ids(month)
      covered_set = (covered + covered.flat_map { |id| rollup.children_of(id) }).to_set
      # A nil key is uncategorized spend — exactly what we must count here,
      # never something to drop.
      rollup.sums(month).reject { |category_id, _| category_id && covered_set.include?(category_id) }
    end

    # End-of-month projection for the current month. Each line projects as
    # what's spent, plus recurring charges still expected this month, plus
    # the rest of the month's day-to-day spend at a rate that blends this
    # month's pace with the category's typical month — early in the month
    # the typical month dominates, so one big day-2 purchase doesn't
    # extrapolate into a wildly overspent forecast.
    sig do
      params(rows: T::Array[T::Hash[Symbol, T.untyped]], other: T::Hash[Symbol, T.untyped])
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def forecast(rows, other)
      return nil unless pace[:current]

      days = @month.end_of_month.day
      elapsed = Date.current.day
      left = days - elapsed
      weight = elapsed.to_f / days
      pending = map_to_lines(charges.pending_by_category)
      paid = map_to_lines(charges.paid_by_category)

      project = lambda do |actual, key, typical|
        upcoming = pending[key] || 0.0
        day_to_day = [ actual - (paid[key] || 0.0), 0.0 ].max
        typical_rest = [ typical - (paid[key] || 0.0) - upcoming, 0.0 ].max
        rate = (weight * day_to_day / elapsed) + ((1 - weight) * typical_rest / days)
        (actual + upcoming + (rate * left)).round(2)
      end

      rows.each { |row| row[:projected] = project.call(row[:actual], row[:category_id], row[:typical]) }
      other[:projected] = project.call(other[:actual], nil, other[:planned]) if other[:planned]

      available = rows.sum { |r| r[:planned] + r[:rollover_amount] } + (other[:planned] || 0)
      projected = rows.sum { |r| r[:projected] } + (other[:projected] || 0)
      overages = rows.filter_map do |r|
        over = r[:projected] - (r[:planned] + r[:rollover_amount])
        next unless over >= 1

        { category_id: r[:category_id], category_name: r[:category_name], over: over.round(2) }
      end

      {
        projected: projected.round(2),
        available: available.round(2),
        over_by:   (projected - available).round(2),
        overages:  overages.sort_by { |o| -o[:over] }.first(3)
      }
    end

    # Re-keys { category_id => amount } onto the line each category's spend
    # counts toward this month (itself, or its budgeted parent); spend that
    # lands on no line keys to nil — "everything else".
    sig { params(by_category: T::Hash[String, Float]).returns(T::Hash[T.nilable(String), Float]) }
    def map_to_lines(by_category)
      budgeted = rollup.budgeted_ids(@month).to_set
      by_category.each_with_object(Hash.new(0.0)) do |(category_id, amount), out|
        parent_id = rollup.category(category_id)&.[](1)
        key =
          if budgeted.include?(category_id) then category_id
          elsif parent_id && budgeted.include?(parent_id) then parent_id
          end
        out[key] += amount
      end
    end

    sig { returns(T.nilable(Float)) }
    def income_suggestion
      months = (1..3).map { |i| @month.months_ago(i) }
      totals = months.map { |m| income_actual_for(m) }
      return nil if totals.all?(&:zero?)

      (totals.sum / 3).round(2).to_f
    end

    sig { params(month: Date).returns(Float) }
    def income_actual_for(month)
      (income_by_month[month] || 0).to_f.round(2)
    end

    # Period amounts carry forward like lines (see BudgetPeriod).
    sig { params(field: Symbol).returns(T.nilable(Float)) }
    def period_value(field)
      period&.[](field)&.to_f
    end

    # How far through the month we are — the reference line for on-pace.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def pace
      today = Date.current
      return { percent_elapsed: 100.0, current: false } if @month.end_of_month < today
      return { percent_elapsed: 0.0, current: false } if @month > today

      { percent_elapsed: ((today.day.to_f / @month.end_of_month.day) * 100).round(1), current: true }
    end

    # ── Window-wide memos ────────────────────────────────────────────────

    sig { returns(Plan) }
    def plan
      @plan ||= Plan.new(through: @month)
    end

    # Spend actuals for the rollover / typical / year-to-date window.
    sig { returns(SpendRollup) }
    def rollup
      @rollup ||= SpendRollup.new(from: @month.months_ago(ROLLOVER_LOOKBACK_MONTHS), to: @month, plan: plan)
    end

    sig { returns(RecurringCharges) }
    def charges
      @charges ||= RecurringCharges.new(month: @month)
    end

    sig { returns(T.nilable(BudgetPeriod)) }
    def period
      return @period if defined?(@period)

      @period = T.let(BudgetPeriod.in_force(@month), T.nilable(BudgetPeriod))
    end

    sig { returns(T::Hash[Date, T.untyped]) }
    def income_by_month
      @income_by_month ||= CashTransaction.income_like
        .where(transaction_date: @month.months_ago(3)..@month.end_of_month)
        .group(Arel.sql("(date_trunc('month', transaction_date))::date"))
        .sum(:amount)
        .transform_keys { |month| month_key(month) }
    end

    # Grouped calculation keys for computed expressions come back untyped on
    # some adapters — normalize to Date so hash lookups line up.
    sig { params(value: T.untyped).returns(Date) }
    def month_key(value)
      value.is_a?(Date) ? value : value.to_date
    end
  end
end
