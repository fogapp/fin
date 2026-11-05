# typed: true

# Weekly tax vigilance scan (docs/tax-center-design.md): for every household
# with a complete current-year tax profile, publishes the workflow events
# Tax::VigilanceScan finds due.
class TaxScanJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    year = Date.current.year

    each_household do |household|
      profile = TaxProfile.find_by(tax_year: year)
      next unless profile&.complete?

      Tax::VigilanceScan.new(household: household, year: year).events.each do |event, payload|
        Workflows::Events.publish(event, subject: household, payload: payload)
      end
    end
  end
end
