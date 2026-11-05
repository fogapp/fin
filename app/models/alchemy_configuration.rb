# typed: true

class AlchemyConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  encrypts :api_key
  encrypts :auth_token
  configured_when :api_key

  # How often the transaction poller runs for this household. Realtime means
  # Alchemy webhooks carry the signal and polling demotes to an hourly
  # reconciliation sweep.
  class SyncFrequency < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Realtime       = new("realtime")
      Every5Minutes  = new("every_5_minutes")
      Every15Minutes = new("every_15_minutes")
      Hourly         = new("hourly")
      Every6Hours    = new("every_6_hours")
      Daily          = new("daily")
    end
  end

  POLL_INTERVALS = T.let({
    SyncFrequency::Realtime       => 1.hour, # safety net under webhooks
    SyncFrequency::Every5Minutes  => 5.minutes,
    SyncFrequency::Every15Minutes => 15.minutes,
    SyncFrequency::Hourly         => 1.hour,
    SyncFrequency::Every6Hours    => 6.hours,
    SyncFrequency::Daily          => 24.hours
  }.freeze, T::Hash[SyncFrequency, ActiveSupport::Duration])

  typed_enum :sync_frequency, SyncFrequency

  sig { returns(T::Boolean) }
  def transactions_configured?
    configured? && transactions_enabled?
  end

  sig { returns(T::Boolean) }
  def realtime?
    sync_frequency == SyncFrequency::Realtime
  end

  sig { returns(ActiveSupport::Duration) }
  def poll_interval
    POLL_INTERVALS.fetch(T.cast(sync_frequency, SyncFrequency))
  end

  sig { returns(T::Boolean) }
  def poll_due?
    last = transactions_last_synced_at
    last.nil? || last <= poll_interval.ago
  end
end
