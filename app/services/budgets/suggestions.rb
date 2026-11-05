# typed: strict

module Budgets
  # Starting points for the plan, per category with spend in the last year:
  # its typical month (median of the last six — robust to a one-off
  # purchase), the trailing-year total (for yearly budgets), recent history,
  # the monthly cost of its recurring charges (a floor), and the unusual
  # charges the typical month leaves out (single charges over twice it), so a
  # suggestion that looks low next to an average can explain itself.
  #
  # History is measured by this month's plan: a parent's spend includes its
  # subcategories except those budgeted on their own now.
  class Suggestions
    extend T::Sig

    RECENT_MONTHS = 6
    UNUSUAL_MIN = 250
    UNUSUAL_SHOWN = 3

    sig { params(month: Date).void }
    def initialize(month:)
      @month = T.let(month.beginning_of_month, Date)
      @plan = T.let(Plan.new(through: @month), Plan)
      @rollup = T.let(SpendRollup.new(from: @month.months_ago(12), to: @month.prev_month.end_of_month, plan: @plan),
                      SpendRollup)
      @budgeted = T.let(@plan.budgeted_ids(@month), T::Array[String])
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      recurring = RecurringCharges.new(month: @month).monthly_by_category
      unusual = unusual_by_category

      rows = candidate_ids.filter_map do |id|
        name, parent_id, = @rollup.category(id)
        next if name.nil?

        recent = recent_months.map { |m| spend(id, m) }
        year_total = (1..12).sum { |i| spend(id, @month.months_ago(i)) }.round(2)
        next if year_total.zero?

        typical = Stats.median(recent).round(2)
        floor = ([ id ] + counted_children(id)).sum { |cid| recurring[cid] || 0.0 }.round(2)
        {
          category_id:       id,
          category_name:     name,
          parent_id:         parent_id,
          parent_name:       parent_id && @rollup.category(parent_id)&.first,
          budgeted:          @budgeted.include?(id),
          typical:           typical,
          suggested:         Stats.round_up5([ typical, floor ].max),
          year_total:        year_total,
          recurring_monthly: floor,
          history:           recent_months.reverse.map { |m| { month: m.strftime("%Y-%m"), actual: spend(id, m) } },
          unusual:           (unusual[id] || []).select { |t| t[:amount] > typical * 2 }.first(UNUSUAL_SHOWN)
        }
      end

      other = recent_months.map { |m| unbudgeted_spend(m) }
      {
        month:           @month.strftime("%Y-%m"),
        categories:      rows.sort_by { |r| -r[:typical] },
        everything_else: { typical: Stats.median(other).round(2), suggested: Stats.round_up5(Stats.median(other)) }
      }
    end

    private

    sig { returns(T::Array[Date]) }
    def recent_months
      @recent_months ||= T.let(@rollup.history_months(@month, RECENT_MONTHS), T.nilable(T::Array[Date]))
    end

    # Categories with spend, plus the parents of subcategories with spend.
    sig { returns(T::Array[String]) }
    def candidate_ids
      ids = @rollup.spent_category_ids
      parents = ids.filter_map { |id| @rollup.category(id)&.[](1) }
      (ids + parents).uniq
    end

    # Subcategories whose spend counts toward the category now.
    sig { params(id: String).returns(T::Array[String]) }
    def counted_children(id)
      @rollup.children_of(id) - @budgeted
    end

    sig { params(id: String, month: Date).returns(Float) }
    def spend(id, month)
      @rollup.spend_excluding(id, month, @budgeted - [ id ])
    end

    sig { params(month: Date).returns(Float) }
    def unbudgeted_spend(month)
      covered = (@budgeted + @budgeted.flat_map { |id| @rollup.children_of(id) }).to_set
      @rollup.sums(month).sum { |id, amount| id && covered.include?(id) ? 0 : amount }.to_f.abs.round(2)
    end

    # Large single charges in the recent window, largest first, listed under
    # their own category and — when they count toward it — their parent.
    sig { returns(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]]) }
    def unusual_by_category
      from = @month.months_ago(RECENT_MONTHS)
      CashTransaction.spend_like
        .where(budget_excluded: false, transaction_date: from..@month.prev_month.end_of_month)
        .where.not(category_id: nil)
        .where("ABS(cash_transactions.amount) >= ?", UNUSUAL_MIN)
        .order(Arel.sql("ABS(cash_transactions.amount) DESC"))
        .pluck(:id, :transaction_date, :description, :amount, :category_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(id, date, description, amount, category_id), out|
          row = { id: id, transaction_date: date.iso8601, description: description, amount: amount.to_f.abs.round(2) }
          out[category_id] << row
          parent_id = @rollup.category(category_id)&.[](1)
          out[parent_id] << row if parent_id && !@budgeted.include?(category_id)
        end
    end
  end
end
