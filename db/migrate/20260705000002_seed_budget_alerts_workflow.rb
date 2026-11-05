# Backfill the seeded budget-alerts workflow for existing households.
class SeedBudgetAlertsWorkflow < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(Households::SeedDefaultWorkflows)

    Household.find_each { |h| Households::SeedDefaultWorkflows.call(h) }
  end

  def down
    Workflow.unscoped.where(seed_key: "budget_alerts").destroy_all
  end
end
