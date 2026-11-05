# typed: true

# Daily scan of every equity grant's vesting schedule: publishes the
# workflow events Equity::VestScan finds due today, with the grant as
# subject.
class EquityVestScanJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    EquityGrant.unscoped.includes(:equity_company, :events).find_each do |grant|
      household = Household.find_by(id: grant.household_id)
      next unless household

      Current.set(household: household) do
        Equity::VestScan.new(grant).events.each do |event, payload|
          Workflows::Events.publish(event, subject: grant, payload: payload)
        end
      end
    rescue => e
      Rails.logger.error("[EquityVestScanJob] grant=#{grant.id} failed: #{e.message}")
    end
  end
end
