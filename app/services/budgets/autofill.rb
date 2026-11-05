# typed: strict

module Budgets
  # A starter plan for a household that hasn't budgeted yet: the few
  # top-level categories that make up most of typical spending (up to
  # MAX_LINES, until COVERAGE of it is covered), each at its suggested
  # amount, plus an "everything else" amount for the rest. Lines are
  # ongoing, so the plan carries forward from `month`. Categories already
  # budgeted are left as they are.
  module Autofill
    extend T::Sig

    MAX_LINES = 8
    COVERAGE = 0.8
    MIN_TYPICAL = 50

    sig { params(month: Date).returns(Integer) }
    def self.call(month:)
      month = month.beginning_of_month
      suggestions = Suggestions.new(month: month).call
      roots = suggestions[:categories].select { |c| c[:parent_id].nil? }
      total = roots.sum { |c| c[:typical] }
      covered = roots.select { |c| c[:budgeted] }.sum { |c| c[:typical] }

      picks = []
      roots.reject { |c| c[:budgeted] }.each do |c|
        break if picks.size >= MAX_LINES || covered >= total * COVERAGE
        next if c[:typical] < MIN_TYPICAL

        picks << c
        covered += c[:typical]
      end

      BudgetLine.transaction do
        picks.each do |c|
          SetLine.set(category: Category.find(c[:category_id]), month: month, planned: c[:suggested])
        end
        if picks.any? && BudgetPeriod.in_force(month)&.other_planned.nil?
          BudgetPeriod.set!(month, other_planned: Suggestions.new(month: month).call[:everything_else][:suggested])
        end
      end
      picks.size
    end
  end
end
