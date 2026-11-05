# typed: true

# Month-level budget amounts: the income target and the "everything else"
# amount (spend outside budgeted categories). Like budget lines they carry
# forward — the latest row on or before a month is in force — so each row
# holds both values as of its month.
class BudgetPeriod < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion

  validates :month, presence: true, uniqueness: { scope: :household_id }
  validate  { T.bind(self, BudgetPeriod); errors.add(:month, "must be the first of the month") unless month.present? && month.day == 1 }

  FIELDS = %i[income_planned other_planned].freeze

  sig { params(month: Date).returns(T.nilable(BudgetPeriod)) }
  def self.in_force(month)
    where(month: ..month.beginning_of_month).order(month: :desc).first
  end

  # Sets values from `month` on: this month's row starts from the values in
  # force, and later rows take the new value too.
  sig { params(month: Date, values: T::Hash[Symbol, T.untyped]).returns(BudgetPeriod) }
  def self.set!(month, values)
    month = month.beginning_of_month
    transaction do
      current = in_force(month)
      period = find_or_initialize_by(month: month)
      FIELDS.each { |f| period[f] = current&.[](f) } if period.new_record?
      period.assign_attributes(values)
      period.save!
      where("month > ?", month).update_all(values) # rubocop:disable Rails/SkipsModelValidations
      period
    end
  end
end
