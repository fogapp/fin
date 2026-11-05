# typed: true

class FxRate < ApplicationRecord
  validates :base, :quote, :date, :rate, :source, presence: true

  # Latest available rate on or before the date; 1.0 for same-currency.
  def self.convert(amount, from:, to: "USD", on: Date.current)
    return amount if from.blank? || from == to

    rate = where(base: from, quote: to).where(date: ..on).order(date: :desc).limit(1).pick(:rate)
    rate ? amount.to_d * rate : nil
  end
end
