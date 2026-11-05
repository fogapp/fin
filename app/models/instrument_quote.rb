# typed: true

# The single "current value" per instrument: latest spot price with its own
# staleness (as_of) and provenance, separate from EOD candle history.
class InstrumentQuote < ApplicationRecord
  belongs_to :security

  validates :price, :currency, :source, :as_of, presence: true
end
