# typed: strict

module Households
  # Per-household cache-version token. Read endpoints embed the current
  # value in their cache keys; any committed financial write bumps it (see
  # BumpsHouseholdDataVersion), so stale entries are simply never read
  # again and age out of the store.
  module DataVersion
    extend T::Sig

    sig { params(household_id: T.untyped).returns(String) }
    def self.current(household_id)
      Rails.cache.fetch(key(household_id)) { Time.current.utc.to_f.to_s }
    end

    sig { params(household_id: T.untyped).void }
    def self.bump!(household_id)
      return if household_id.blank?
      Rails.cache.write(key(household_id), Time.current.utc.to_f.to_s)
    end

    # Coalesced bump: at most two cache writes per household per request/job
    # instead of one per committed record (a 2,000-row import used to issue
    # 2,000 identical solid_cache writes). The first call bumps immediately
    # so concurrent readers rotate right away; repeats within the same
    # executor unit of work are deferred and flushed as one final bump when
    # Current resets (see Current#before_reset), so the version also rotates
    # past anything cached mid-request. Outside the executor (console, rake)
    # there is no guaranteed reset to flush from, so every call bumps
    # immediately — the pre-coalescing behavior.
    sig { params(household_id: T.untyped).void }
    def self.bump_coalesced!(household_id)
      return if household_id.blank?
      return bump!(household_id) unless Rails.application.executor.active?

      bumped = (Current.data_version_bumped_ids ||= Set.new)
      if bumped.add?(household_id)
        bump!(household_id)
      else
        (Current.data_version_pending_ids ||= Set.new) << household_id
      end
    end

    # Invoked from Current's before_reset hook at the end of each request/job.
    sig { void }
    def self.flush_pending_bumps!
      pending = Current.data_version_pending_ids
      return if pending.blank?

      Current.data_version_pending_ids = nil
      pending.each { |household_id| bump!(household_id) }
    end

    sig { params(household_id: T.untyped).returns(String) }
    def self.key(household_id)
      "households/#{household_id}/data_version"
    end
  end
end
