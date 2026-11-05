# typed: true

# Pins exactly one provider per (instrument, capability) and tracks its
# health. The scheduler consults consecutive_failures/last_attempt_at for
# exponential backoff and skips disabled links.
class InstrumentDataLink < ApplicationRecord
  belongs_to :security

  typed_enum :capability, MarketData::Capability
  typed_enum :provider, MarketData::Provider
  validates :capability, uniqueness: { scope: :security_id }

  scope :enabled, -> { where(disabled: false) }

  BACKOFF_BASE = 30.minutes

  def in_backoff?
    attempted_at = last_attempt_at
    return false if consecutive_failures.zero? || attempted_at.nil?

    delay = BACKOFF_BASE * (2**[ consecutive_failures - 1, 5 ].min)
    attempted_at + delay > Time.current
  end

  def record_success!
    update!(consecutive_failures: 0, last_success_at: Time.current,
            last_attempt_at: Time.current, last_error: nil)
  end

  def record_failure!(error)
    update!(consecutive_failures: consecutive_failures + 1,
            last_attempt_at: Time.current, last_error: error.to_s.truncate(255))
  end
end
