# typed: true

# One estimated-tax payment the household actually made (a RECORD in the
# tax center's fact/record/estimate taxonomy — the IRS won't tell us).
# Quarters are derived from paid_on against the year's due-date windows,
# never stored.
class EstimatedTaxPayment < ApplicationRecord
  include HouseholdScoped
  # Feeds the cached tax report (render_cached), so writes must rotate the key.
  include BumpsHouseholdDataVersion

  # A single payment goes to exactly one authority, so "both" is excluded:
  # the attribute reads/writes Tax::Jurisdiction, with the inclusion
  # validation scoped to the Federal/State subset (same shape typed_enum
  # generates, minus Both).
  JURISDICTIONS = [ Tax::Jurisdiction::Federal, Tax::Jurisdiction::State ].freeze

  attribute :jurisdiction, ApplicationRecord::EnumType.new(Tax::Jurisdiction)
  validates :jurisdiction, inclusion: { in: JURISDICTIONS }

  validates :tax_year, presence: true,
                       numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :paid_on, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
end
