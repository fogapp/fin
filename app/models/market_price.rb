# typed: true

class MarketPrice < ApplicationRecord
  belongs_to :security

  validates :date, presence: true
  validates :date, uniqueness: { scope: :security_id }

  scope :chronological, -> { order(:date) }
end
