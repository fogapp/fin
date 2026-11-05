# typed: true

# An arbitrary per-year tax line item — the escape hatch that makes any
# year's situation representable without new code. K-1s and rental income
# flow in as kind "income", property tax as "deduction", off-ledger 401(k)
# payroll deferrals as "contribution" (with a bucket), etc. The year report
# folds each kind into its section.
class TaxAdjustment < ApplicationRecord
  include HouseholdScoped
  # Feeds the cached tax report (render_cached), so writes must rotate the key.
  include BumpsHouseholdDataVersion

  # Which section of the year report the line item folds into.
  class Kind < T::Enum
    include ApplicationEnum

    enums do
      Income       = new("income")
      Deduction    = new("deduction")
      Credit       = new("credit")
      Payment      = new("payment")
      Contribution = new("contribution")
    end
  end

  BUCKETS = Tax::Parameters::CONTRIBUTION_BUCKET_KEYS

  typed_enum :kind, Kind
  typed_enum :jurisdiction, Tax::Jurisdiction

  validates :tax_year, presence: true,
                       numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :label, presence: true
  validates :amount, presence: true, numericality: true
  validates :bucket, inclusion: { in: BUCKETS }, allow_nil: true
  validate :bucket_only_for_contributions

  private

  def bucket_only_for_contributions
    return if bucket.blank? || kind == Kind::Contribution

    errors.add(:bucket, "only applies to contribution adjustments")
  end
end
