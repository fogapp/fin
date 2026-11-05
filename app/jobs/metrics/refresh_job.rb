# typed: true

module Metrics
  # Nightly cron (config/recurring.yml): refreshes metric points for every
  # household. Same per-household Current.set sweep as
  # Workflows::MonitorSweepJob — a failure in one household logs and moves
  # on rather than aborting the sweep.
  class RefreshJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, key: -> { "metrics_refresh" }

    def perform
      each_household { Metrics::Refresh.new.call }
    end
  end
end
