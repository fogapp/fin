# typed: true

# One point on a company's fair-market-value history. Private companies only
# expose their current 409A, so the history is manually maintained; entries
# older than 12 months are flagged stale.
class EquityFmvEntry < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # An FMV point reprices every grant at that company, which net worth caches.
  include BumpsHouseholdDataVersion

  # Where the price point came from. "409a" isn't a legal Ruby constant
  # name, hence FourOhNineA.
  class Source < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      FourOhNineA = new("409a")
      Round = new("round")
      Tender = new("tender")
      Market = new("market")
      Manual = new("manual")
    end
  end

  belongs_to :equity_company

  typed_enum :source, Source

  validates :price_per_share, presence: true, numericality: { greater_than: 0 }
  validates :effective_date, presence: true, uniqueness: { scope: :equity_company_id }

  sig { returns(T::Boolean) }
  def stale?
    effective_date < 12.months.ago.to_date
  end
end
