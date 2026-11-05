# typed: true

module RealEstate
  # Refreshes one property from RentCast. Used by the weekly fan-out and by
  # the "Refresh now" button.
  class RefreshJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: ->(_household_id, property_id) { property_id }

    # A quota failure is a state of the world, not a transient fault —
    # retrying just re-raises until the month rolls. The refresher has
    # already recorded an Issue by this point.
    discard_on RentcastConfiguration::QuotaExceeded

    sig { params(household_id: String, property_id: String, force_facts: T::Boolean).void }
    def perform(household_id, property_id, force_facts: false)
      household = Household.find(household_id)
      Current.set(household: household) do
        property = RealEstateProperty.find(property_id)
        PropertyRefresher.new(property, force_facts: force_facts).call
        Rails.logger.info(
          "[RealEstate::RefreshJob] household=#{household_id} property=#{property_id} " \
          "value=#{property.current_value}"
        )
      end
    end
  end
end
