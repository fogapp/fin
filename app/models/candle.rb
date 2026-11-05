# typed: true

class Candle < ApplicationRecord
  # The only granularity written today. A single-value vocabulary isn't an
  # enum — providers and scopes share the constant instead.
  GRANULARITY_DAILY = "1d"

  belongs_to :security

  validates :date, :close, :currency, :source, presence: true

  scope :daily,         -> { where(granularity: GRANULARITY_DAILY) }
  scope :chronological, -> { order(:date) }
end
