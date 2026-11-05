# typed: true

module Recurring
  # Entry point for the recurring pipeline, per household:
  # match new transactions onto accepted series, advance time-based
  # occurrence states, then detect new suggestions from what's left.
  # Enqueued after Plaid syncs and CSV imports; also runs nightly.
  class DetectJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { params(household_id: T.nilable(String)).void }
    def perform(household_id: nil)
      households = household_id ? Household.where(id: household_id) : Household.all
      households.find_each do |household|
        Current.set(household: household) do
          Matcher.run
          Monitor.run
          stats = Detector.run

          if stats.created.positive? || stats.refreshed.positive?
            Activity.record(
              source: "recurring_detection", event: "detection.completed",
              summary: "Recurring detection: #{stats.created} new suggestions, #{stats.refreshed} refreshed",
              payload: { created: stats.created, refreshed: stats.refreshed }
            )
          end
        end
      end
    end
  end
end
