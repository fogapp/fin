# typed: true

# One tax profile per (household, tax_year): the small set of user-entered
# facts the exercise planner's tax engines need. `complete?` gates the
# planner endpoint — without projected wages every downstream number would
# be meaningless.
class TaxProfile < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # Feeds the cached tax report (render_cached), so writes must rotate the key.
  include BumpsHouseholdDataVersion

  typed_enum :filing_status, Tax::FilingStatus

  validates :tax_year, presence: true,
                       numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :tax_year, uniqueness: { scope: :household_id }
  validates :state, inclusion: { in: Tax::States::CODES }
  validates :projected_wages, :other_ordinary_income, :ltcg_qd_income, :salt_paid,
            :itemized_other, :ytd_withholding_federal, :ytd_withholding_state,
            :amt_credit_carryforward_federal, :amt_credit_carryforward_ca,
            numericality: { greater_than_or_equal_to: 0 }
  validates :prior_year_total_tax, :prior_year_agi, :projected_state_tax,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :projected_state_tax_entered_where_not_modeled

  sig { returns(T::Boolean) }
  def complete?
    projected_wages.to_d.positive?
  end

  # Where the year report's state tax comes from; see Tax::States.
  sig { returns(Tax::States::Source) }
  def state_tax_source
    T.must(Tax::States.source(state, projected_state_tax))
  end

  private

  def projected_state_tax_entered_where_not_modeled
    return unless Tax::States::CODES.include?(state)
    return if Tax::States.source(state, projected_state_tax)

    errors.add(:projected_state_tax, "is required for #{Tax::States.name_for(state)} — Fin only estimates California")
  end
end
