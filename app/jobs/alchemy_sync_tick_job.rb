# typed: true

# Cron fan-out for the 6-hourly Alchemy balance sync: a schedulable class
# instead of the inline Ruby `command:` entry recurring.yml used to carry.
# The configured? check stays inside AlchemySyncJob too — other paths
# (manual sync endpoint, wallet/config controllers, workflow trigger_sync,
# backfill finalization) enqueue it directly.
class AlchemySyncTickJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    each_household do |household|
      AlchemySyncJob.perform_later(household.id) if AlchemyConfiguration.current.configured?
    end
  end
end
