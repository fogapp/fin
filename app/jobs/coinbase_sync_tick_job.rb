# typed: true

# Cron fan-out for the 6-hourly Coinbase sync: a schedulable class instead
# of the inline Ruby `command:` entry recurring.yml used to carry. The
# configured? check stays inside CoinbaseSyncJob too — other paths (manual
# sync endpoint, workflow trigger_sync) enqueue it directly.
class CoinbaseSyncTickJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    each_household do |household|
      CoinbaseSyncJob.perform_later(household.id) if Coinbase.configured?
    end
  end
end
