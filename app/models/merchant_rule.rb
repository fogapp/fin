# typed: true

class MerchantRule < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  belongs_to :merchant
  belongs_to :category, optional: true

  validates :pattern, presence: true
  validate :pattern_is_valid_regex

  private

  sig { void }
  def pattern_is_valid_regex
    return if pattern.blank?
    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regular expression: #{e.message}")
  end
end
