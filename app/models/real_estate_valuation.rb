# typed: true

# One point on a property's value chart. See RealEstateProperty for how
# these resolve into "the property's current value".
class RealEstateValuation < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion

  # Where the number came from. Only MARKET_SOURCES count as the property's
  # value; tax assessments run well below market (the ratio varies by
  # county) and are charted as a dimmed reference line instead.
  class Source < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Rentcast      = new("rentcast")
      Manual        = new("manual")
      Purchase      = new("purchase")
      Sale          = new("sale")
      TaxAssessment = new("tax_assessment")
    end
  end

  MARKET_SOURCES = T.let(
    [ Source::Manual, Source::Rentcast, Source::Sale, Source::Purchase ].freeze,
    T::Array[Source]
  )

  # Same-day tiebreak for "newest date wins": a value you typed today beats
  # the estimate this morning's sync recorded, and next week's sync beats it
  # back. Higher wins.
  SOURCE_RANK = T.let(
    { "manual" => 4, "rentcast" => 3, "sale" => 2, "purchase" => 1, "tax_assessment" => 0 }.freeze,
    T::Hash[String, Integer]
  )

  typed_enum :source, Source

  belongs_to :real_estate_property

  validates :as_of, :amount, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :chronological, -> { order(:as_of) }

  # Ordering key for "which valuation is current" — newest date, then
  # source precedence, then most recently written. Only called on persisted
  # rows (everything reaches it through the property's association), so
  # created_at is always set.
  sig { returns([ Date, Integer, Float ]) }
  def precedence
    [ as_of, SOURCE_RANK.fetch(source.to_s, 0), created_at.to_f ]
  end
end
