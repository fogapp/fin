# typed: true

module Alchemy
  # Reconciles the household's Alchemy webhooks with the desired state after
  # configuration or wallet changes. Cheap no-op when real-time sync is off.
  class WebhookSyncJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: ->(household_id) { "alchemy_webhooks:#{household_id}" }

    sig { params(household_id: String).void }
    def perform(household_id)
      household = Household.find(household_id)
      Current.set(household: household) do
        WebhookManager.new.sync!
      end
    end
  end
end
