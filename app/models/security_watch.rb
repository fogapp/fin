# typed: true

# A household's watchlist membership for a (globally shared) security.
class SecurityWatch < ApplicationRecord
  include HouseholdScoped
  # Watch/unwatch must rotate the cached /market index and summary payloads.
  include BumpsHouseholdDataVersion

  belongs_to :security

  validates :security_id, uniqueness: { scope: :household_id }
end
