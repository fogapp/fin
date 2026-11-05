# typed: true

module RealEstate
  # Weekly fan-out: one RefreshJob per syncable property, for every
  # household with RentCast configured.
  #
  # Budget guard — the free tier allows 50 requests a month, and a property
  # whose facts cache has expired costs two. If the remaining allowance
  # can't cover this run in full, nothing is enqueued and an Issue explains
  # the shortfall. Syncing all-or-nothing keeps the properties' value curves
  # sampled on the same days, which a partial run would stagger.
  class SyncTickJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: "real_estate_sync_tick"

    sig { void }
    def perform
      each_household do |household|
        config = RentcastConfiguration.current
        next unless config.configured?

        sync_household(household, config)
      end
    end

    private

    sig { params(household: Household, config: RentcastConfiguration).void }
    def sync_household(household, config)
      properties = RealEstateProperty.syncable.includes(:valuations).to_a
      return if properties.empty?

      cost      = properties.sum { |property| request_cost(property) }
      remaining = config.remaining_quota

      if cost > remaining
        Issue.raise_once!(
          key:      "rentcast_quota_#{household.id}",
          title:    "RentCast sync skipped — monthly quota too low",
          body:     "This week's sync needs #{cost} requests but only #{remaining} of " \
                    "#{config.monthly_request_limit} remain this month. Property values will be stale " \
                    "until the allowance resets on #{Date.current.next_month.beginning_of_month.to_fs(:long)}.",
          severity: Severity::Warning,
          source:   "rentcast"
        )
        return
      end

      Issue.resolve!("rentcast_quota_#{household.id}")
      properties.each { |property| RefreshJob.perform_later(household.id, property.id) }
      config.update!(last_synced_at: Time.current)
      Rails.logger.info("[RealEstate::SyncTickJob] household=#{household.id} properties=#{properties.size} cost=#{cost}")
    end

    # One AVM call always, plus a record call when the facts cache has aged
    # out (roughly quarterly per property).
    sig { params(property: RealEstateProperty).returns(Integer) }
    def request_cost(property)
      synced = property.facts_synced_at
      synced.nil? || synced < RealEstateProperty::FACTS_TTL.ago ? 2 : 1
    end
  end
end
