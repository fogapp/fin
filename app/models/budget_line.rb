# typed: true

# One planned amount for one category, effective from `month`. The household
# sets a budget once and it carries forward (see Budgets::Plan):
#
#   ongoing    — applies from this month until a later ongoing/stopped line
#   month_only — applies to this month alone; later months fall back to the
#                ongoing line in force
#   stopped    — the category is no longer budgeted from this month on
#
# A yearly line's planned is an annual amount, measured against spend so far
# in the calendar year. Rollover carries a monthly line's unspent (or
# overspent) remainder into the next month's remaining:
#   remaining = rollover(prev chain) + planned - actual
class BudgetLine < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion

  class Mode < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Ongoing = new("ongoing")
      MonthOnly = new("month_only")
      Stopped = new("stopped")
    end
  end

  class Period < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Monthly = new("monthly")
      Yearly = new("yearly")
    end
  end

  belongs_to :category

  typed_enum :mode, Mode
  typed_enum :period, Period

  validates :month, presence: true
  validates :planned, numericality: { greater_than_or_equal_to: 0 }
  validates :category_id, uniqueness: { scope: %i[household_id month] }
  validate  { T.bind(self, BudgetLine); errors.add(:month, "must be the first of the month") unless month.present? && month.day == 1 }

  scope :for_month, ->(month) { where(month: month.beginning_of_month) }

  sig { returns(T::Boolean) }
  def yearly?
    period == Period::Yearly
  end
end
