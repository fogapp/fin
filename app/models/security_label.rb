# typed: true

# A household's own display name for a (globally shared) security. Holdings
# fall back to ticker, then to the custodian description, when none is set.
class SecurityLabel < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # Labels appear in the cached /portfolio and /crypto payloads.
  include BumpsHouseholdDataVersion

  belongs_to :security

  validates :label, presence: true
  validates :security_id, uniqueness: { scope: :household_id }

  normalizes :label, with: ->(l) { l.to_s.strip }

  # security_id => label, for the current household.
  sig { params(security_ids: T::Array[T.untyped]).returns(T::Hash[String, String]) }
  def self.by_security(security_ids)
    return {} if security_ids.empty?

    where(security_id: security_ids).pluck(:security_id, :label).to_h
  end
end
