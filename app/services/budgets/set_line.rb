# typed: strict

module Budgets
  # Edits the standing plan for one category, as of a month.
  #
  #   set  (ongoing)    — the amount from `month` on: later ongoing/stopped
  #                       lines are superseded and removed; later month-only
  #                       overrides stay.
  #   set  (month_only) — the amount for `month` alone. If the line being
  #                       replaced was the ongoing one set this very month,
  #                       it moves to next month so the plan still carries.
  #   stop              — the category stops being budgeted from `month` on.
  #   clear_override    — drops a month-only amount, so the month falls back
  #                       to the ongoing plan.
  #
  # Past months are never touched: history keeps the plan that was in force.
  module SetLine
    extend T::Sig

    sig do
      params(category: Category, month: Date, planned: T.nilable(Numeric), rollover: T.nilable(T::Boolean),
             period: T.nilable(BudgetLine::Period), mode: BudgetLine::Mode).returns(BudgetLine)
    end
    def self.set(category:, month:, planned: nil, rollover: nil, period: nil,
                 mode: BudgetLine::Mode::Ongoing)
      month = month.beginning_of_month
      raise ArgumentError, "use SetLine.stop to stop a budget" if mode == BudgetLine::Mode::Stopped

      BudgetLine.transaction do
        current = Plan.new(through: month).line_for(category.id, month)
        line = BudgetLine.find_or_initialize_by(category_id: category.id, month: month)

        if mode == BudgetLine::Mode::MonthOnly && line.persisted? && line.mode == BudgetLine::Mode::Ongoing
          carry_to_next_month(line)
        end
        if mode == BudgetLine::Mode::Ongoing
          later(category, month).where(mode: [ BudgetLine::Mode::Ongoing, BudgetLine::Mode::Stopped ].map(&:serialize)).destroy_all
        end

        line.assign_attributes(
          mode:     mode,
          planned:  planned || current&.planned || 0,
          rollover: rollover.nil? ? (current&.rollover || false) : rollover,
          period:   period || current&.period || BudgetLine::Period::Monthly
        )
        line.rollover = false if line.yearly?
        line.save!
        line
      end
    end

    sig { params(category: Category, month: Date).void }
    def self.stop(category:, month:)
      month = month.beginning_of_month
      BudgetLine.transaction do
        BudgetLine.for_month(month).where(category_id: category.id).destroy_all
        later(category, month).destroy_all
        if Plan.new(through: month).line_for(category.id, month)
          BudgetLine.create!(category: category, month: month, mode: BudgetLine::Mode::Stopped, planned: 0)
        end
      end
    end

    sig { params(category: Category, month: Date).void }
    def self.clear_override(category:, month:)
      BudgetLine.for_month(month).where(category_id: category.id, mode: BudgetLine::Mode::MonthOnly.serialize).destroy_all
    end

    sig { params(category: Category, month: Date).returns(T.untyped) }
    def self.later(category, month)
      BudgetLine.where(category_id: category.id).where("month > ?", month)
    end
    private_class_method :later

    sig { params(line: BudgetLine).void }
    def self.carry_to_next_month(line)
      next_month = line.month.next_month
      return if BudgetLine.exists?(category_id: line.category_id, month: next_month)

      BudgetLine.create!(category_id: line.category_id, month: next_month, mode: BudgetLine::Mode::Ongoing,
                         planned: line.planned, rollover: line.rollover, period: line.period)
    end
    private_class_method :carry_to_next_month
  end
end
