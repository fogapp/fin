# typed: true

module Metrics
  # Recomputes one metric's full history for one household — for changes
  # that rewrite the past (a confirmed security conversion revalues history
  # the nightly refresh's trailing window never reaches).
  class BackfillJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(household_id, key) { "metrics_backfill:#{household_id}:#{key}" }

    def perform(household_id, key)
      definition = Metrics::Registry.find(key.to_s)
      return unless definition

      with_household(household_id) { Metrics::Backfill.new.call(definition, reset: true) }
    end
  end
end
