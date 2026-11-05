# typed: strict
# frozen_string_literal: true

# Instance-wide state that belongs to no household — one row, created on
# first use. It remembers when Fin proved it runs on fog (FogSignin) and
# holds the instance's time zone.
#
# The time zone is instance-wide rather than per household: "today", month
# boundaries, the cron schedules in config/recurring.yml and market-sync days
# are all computed app-wide. Every request (InstanceTimeZone, mixed into all
# controllers) and every job (ApplicationJob) runs inside
# Time.use_zone(InstanceSetting.time_zone); config.time_zone stays the boot
# default for console and rake.
class InstanceSetting < ApplicationRecord
  extend T::Sig

  # Matches the column default and config.time_zone in config/application.rb.
  DEFAULT_TIME_ZONE = "America/Los_Angeles"

  # How long a process trusts its memoized zone. The process that saves a
  # change drops its copy at once; other processes (Puma workers, the job
  # worker) pick the change up within this window.
  TIME_ZONE_CACHE_TTL = 30 # seconds

  @time_zone_cache = T.let(nil, T.nilable([ String, Float ]))

  before_validation :normalize_time_zone
  validate :time_zone_known
  after_commit :time_zone_changed, if: :saved_change_to_time_zone?

  sig { returns(InstanceSetting) }
  def self.current
    find_by(singleton: true) || create!(singleton: true)
  rescue ActiveRecord::RecordNotUnique
    # Another process created the row between the lookup and the insert.
    find_by!(singleton: true)
  end

  class << self
    extend T::Sig

    # The IANA identifier every request and job runs in. Read on every
    # request, so it is memoized per process (see TIME_ZONE_CACHE_TTL) and
    # never creates the row — a fresh instance simply reads the default.
    sig { returns(String) }
    def time_zone
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cached = @time_zone_cache
      return cached[0] if cached && now < cached[1]

      zone = load_time_zone
      @time_zone_cache = [ zone, now + TIME_ZONE_CACHE_TTL ]
      zone
    end

    sig { void }
    def reset_time_zone_cache!
      @time_zone_cache = nil
    end

    # Zones offered in Settings: tzdata's location zones, every zone Rails
    # names (some, like Europe/Amsterdam, are links tzdata no longer lists by
    # country), and UTC — without the legacy aliases (US/Pacific, EST5EDT, …)
    # that the validation still accepts. Rails' friendly names ride along so
    # "Pacific Time" finds America/Los_Angeles.
    sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
    def selectable_time_zones
      zone_identifiers.map do |id|
        zone = ActiveSupport::TimeZone[id]
        { id: id, name: rails_zone_names[id], utc_offset: zone&.now&.formatted_offset }
      end
    end

    # The IANA identifier for a Rails zone name ("Pacific Time (US &
    # Canada)") or an IANA identifier, or nil when neither names a zone.
    sig { params(value: T.untyped).returns(T.nilable(String)) }
    def iana_time_zone(value)
      return nil unless value.is_a?(String) && value.present?

      ActiveSupport::TimeZone[value.strip]&.tzinfo&.name
    end

    private

    sig { returns(String) }
    def load_time_zone
      # with_connection: the Solid Queue scheduler reads this from its own
      # timer threads, outside any executor — don't strand a connection there.
      stored = with_connection { where(singleton: true).pick(:time_zone) }
      iana_time_zone(stored) || DEFAULT_TIME_ZONE
    rescue ActiveRecord::ActiveRecordError => e
      # No database (or the column isn't migrated yet): run in the default
      # rather than failing every request.
      Rails.logger.warn("[InstanceSetting] time zone unavailable, using #{DEFAULT_TIME_ZONE}: #{e.class}: #{e.message}")
      DEFAULT_TIME_ZONE
    end

    sig { returns(T::Array[String]) }
    def zone_identifiers
      @zone_identifiers ||= T.let(
        (TZInfo::Timezone.all_country_zone_identifiers + ActiveSupport::TimeZone::MAPPING.values + [ "Etc/UTC" ]).uniq.sort.freeze,
        T.nilable(T::Array[String])
      )
    end

    sig { returns(T::Hash[String, String]) }
    def rails_zone_names
      @rails_zone_names ||= T.let(
        ActiveSupport::TimeZone::MAPPING.each_with_object({}) { |(name, id), names| names[id] ||= name }.freeze,
        T.nilable(T::Hash[String, String])
      )
    end
  end

  private

  # Accept a Rails zone name or an IANA identifier; store the IANA one.
  sig { void }
  def normalize_time_zone
    iana = self.class.iana_time_zone(time_zone)
    self.time_zone = iana if iana
  end

  sig { void }
  def time_zone_known
    return if self.class.iana_time_zone(time_zone)

    errors.add(:time_zone, "is not a known time zone")
  end

  sig { void }
  def time_zone_changed
    self.class.reset_time_zone_cache!
    # Calendar schedules (daily at 05:30, …) were resolved to an instant in
    # the old zone; move the pending ones to the same wall-clock time in the
    # new one.
    Time.use_zone(time_zone) { Workflow.reanchor_calendar_schedules! }
  end
end
