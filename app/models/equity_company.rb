# typed: true

# A company the household holds equity compensation in — private (valued via
# the manual FMV history) or public (linked to a Security for live quotes).
class EquityCompany < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion

  belongs_to :security, optional: true
  has_many :fmv_entries, class_name: "EquityFmvEntry", dependent: :destroy
  has_many :grants, class_name: "EquityGrant", dependent: :destroy

  validates :name, presence: true

  sig { returns(T.nilable(EquityFmvEntry)) }
  def latest_fmv
    if fmv_entries.loaded?
      fmv_entries.max_by(&:effective_date)
    else
      fmv_entries.order(effective_date: :desc).first
    end
  end

  # Resolved per-share price: public quote when linked, latest FMV otherwise.
  sig { returns(T.nilable(BigDecimal)) }
  def current_share_price
    Equity::Valuation.current_share_price(self)
  end
end
