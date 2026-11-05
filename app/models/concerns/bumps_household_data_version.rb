# typed: false

# Bumps the owning household's DataVersion after any committed write so the
# cached read endpoints (net worth, portfolio, cashflow, dashboard, budget)
# stop serving entries computed from the old data. Bulk writes that skip
# callbacks (upsert_all/insert_all/update_all/update_columns) must bump
# explicitly — the endpoint cache TTL bounds the damage if one is missed.
#
# Bumps are coalesced per request/job via DataVersion.bump_coalesced!: the
# first committed write bumps immediately, repeats within the same executor
# unit of work are deferred and flushed as one final bump when Current resets
# at the end of the request/job — so a 2,000-row import issues 2 solid_cache
# writes instead of 2,000. Outside the executor (console, rake) every write
# still bumps immediately.
#
# Models without a household_id column name the association that reaches
# one: `bumps_data_version_via :account`.
module BumpsHouseholdDataVersion
  extend ActiveSupport::Concern

  included do
    class_attribute :data_version_household_via, instance_accessor: false, default: nil
    after_commit :bump_household_data_version
  end

  class_methods do
    def bumps_data_version_via(association)
      self.data_version_household_via = association
    end
  end

  private

  def bump_household_data_version
    via = self.class.data_version_household_via
    household_id = via ? public_send(via)&.household_id : self.household_id
    Households::DataVersion.bump_coalesced!(household_id)
  end
end
