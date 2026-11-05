# typed: strict

module Budgets
  # The standing plan: which budget line is in force for each category in a
  # given month. A household sets a budget once and it carries forward —
  #
  #   - a month_only line at exactly that month wins;
  #   - otherwise the latest ongoing or stopped line on or before the month
  #     applies, and a stopped line means "not budgeted".
  #
  # Loads every line up to `through` once (a household has a few dozen at
  # most) and resolves any earlier month in memory.
  class Plan
    extend T::Sig

    sig { params(through: Date).void }
    def initialize(through:)
      @through = T.let(through.beginning_of_month, Date)
      @by_category = T.let(nil, T.nilable(T::Hash[String, T::Array[BudgetLine]]))
      @resolved = T.let({}, T::Hash[Date, T::Hash[String, BudgetLine]])
    end

    # Lines in force for the month, keyed by category id.
    sig { params(month: Date).returns(T::Hash[String, BudgetLine]) }
    def in_force(month)
      month = month.beginning_of_month
      raise ArgumentError, "#{month} is past the plan's horizon #{@through}" if month > @through

      @resolved[month] ||= by_category.each_with_object({}) do |(category_id, lines), out|
        line = resolve(lines, month)
        out[category_id] = line if line
      end
    end

    sig { params(month: Date).returns(T::Array[BudgetLine]) }
    def lines_for(month)
      in_force(month).values
    end

    sig { params(category_id: String, month: Date).returns(T.nilable(BudgetLine)) }
    def line_for(category_id, month)
      in_force(month)[category_id]
    end

    sig { params(month: Date).returns(T::Array[String]) }
    def budgeted_ids(month)
      in_force(month).keys
    end

    # { first-of-month => budgeted category ids } for SpendRollup.
    sig { params(months: T::Enumerable[Date]).returns(T::Hash[Date, T::Array[String]]) }
    def budgeted_ids_by_month(months)
      months.to_h { |m| [ m.beginning_of_month, budgeted_ids(m) ] }
    end

    # True when the household has ever budgeted anything up to the horizon.
    sig { returns(T::Boolean) }
    def any?
      by_category.any?
    end

    private

    # Lines are sorted newest first; the first month_only line at the month
    # or the first ongoing/stopped line at or before it decides.
    sig { params(lines: T::Array[BudgetLine], month: Date).returns(T.nilable(BudgetLine)) }
    def resolve(lines, month)
      lines.each do |line|
        next if line.month > month

        case line.mode
        when BudgetLine::Mode::MonthOnly
          return line if line.month == month
        when BudgetLine::Mode::Stopped
          return nil
        else
          return line
        end
      end
      nil
    end

    sig { returns(T::Hash[String, T::Array[BudgetLine]]) }
    def by_category
      @by_category ||= BudgetLine.where(month: ..@through)
        .includes(category: :parent)
        .order(month: :desc)
        .group_by(&:category_id)
    end
  end
end
