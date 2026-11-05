# typed: strict

module Budgets
  # The year-at-a-glance grid behind the budget calendar view: one row per
  # category the plan covers at any point in the year, one cell per month
  # with the amount in force (nil where not budgeted), whether that month
  # has its own one-month amount, and the actual spend. A yearly line's
  # cells carry no monthly amount; its row carries the annual one.
  #
  # Everything derives from the plan plus the Budgets::SpendRollup's
  # window-wide queries, sliced in memory — never twelve Month instances.
  class Calendar
    extend T::Sig

    sig { params(year: Integer).void }
    def initialize(year:)
      @year = year
      @plan = T.let(Plan.new(through: Date.new(year, 12, 1)), Plan)
      @rollup = T.let(nil, T.nilable(SpendRollup))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      months = (1..12).map { |m| Date.new(@year, m, 1) }
      month_keys = months.map { |m| m.strftime("%Y-%m") }
      in_force = months.to_h { |m| [ m, @plan.in_force(m) ] }
      category_ids = in_force.values.flat_map(&:keys).uniq

      rows = category_ids.map do |category_id|
        name, parent_id = rollup.category(category_id)
        lines = months.to_h { |m| [ m, in_force.dig(m, category_id) ] }
        yearly_line = lines.values.compact.reverse.find(&:yearly?)

        cells = months.to_h do |m|
          line = lines[m]
          [
            m.strftime("%Y-%m"),
            {
              planned:  line && !line.yearly? ? line.planned.to_f.round(2) : nil,
              override: line&.mode == BudgetLine::Mode::MonthOnly,
              actual:   rollup.spend(category_id, m)
            }
          ]
        end

        {
          category_id:   category_id,
          category_name: name,
          parent_id:     parent_id,
          period:        yearly_line ? BudgetLine::Period::Yearly : BudgetLine::Period::Monthly,
          annual:        yearly_line&.planned&.to_f,
          months:        cells,
          total_planned: (cells.values.sum { |c| c[:planned] || 0.0 } + (yearly_line ? yearly_line.planned.to_f : 0.0)).round(2),
          total_actual:  cells.values.sum { |c| c[:actual] }.round(2)
        }
      end

      rows.sort_by! { |row| [ row[:period] == BudgetLine::Period::Yearly ? 1 : 0, -row[:total_planned] ] }

      totals = month_keys.to_h do |key|
        [
          key,
          {
            planned:  rows.sum { |row| row[:months][key][:planned] || 0.0 }.round(2),
            override: false,
            actual:   rows.sum { |row| row[:months][key][:actual] }.round(2)
          }
        ]
      end

      { year: @year, months: month_keys, rows: rows, totals: totals }
    end

    private

    sig { returns(SpendRollup) }
    def rollup
      @rollup ||= SpendRollup.new(from: Date.new(@year, 1, 1), to: Date.new(@year, 12, 31), plan: @plan)
    end
  end
end
