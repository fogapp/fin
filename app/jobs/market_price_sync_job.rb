# typed: true

class MarketPriceSyncJob < ApplicationJob
  extend T::Sig

  # Dedicated queue with its own single-thread worker (config/queue.yml):
  # the scheduler paces provider calls with in-thread sleeps, which would
  # otherwise pin one of the main pool's three threads for minutes.
  queue_as :market_data
  # Overlapping runs double the provider call budgets.
  limits_concurrency to: 1, key: -> { "market_price_sync" }

  sig { void }
  def perform
    sync_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = MarketData::Scheduler.new.run
    duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - sync_started) * 1000
    Rails.logger.info("[MarketPriceSyncJob] synced=#{result.synced} skipped=#{result.skipped} failed=#{result.failed}")

    each_household do |household|
      Activity.record(
        source: "market_prices", event: "sync.completed",
        severity: result.failed.positive? ? Severity::Warning : Severity::Info,
        summary: "Market data sync: #{result.synced} instruments" \
                 "#{result.failed.positive? ? ", #{result.failed} failed" : ''}" \
                 "#{result.skipped.positive? ? ", #{result.skipped} in backoff" : ''}",
        payload: { synced: result.synced, failed: result.failed, skipped: result.skipped },
        duration_ms: duration_ms, household_id: household.id
      )
    end
  end
end
