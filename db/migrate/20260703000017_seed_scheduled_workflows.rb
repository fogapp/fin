# Backfills the default scheduled workflows (market sync, audits, syncs —
# formerly recurring.yml entries and settings screens) for existing
# households. New households are seeded at creation.
class SeedScheduledWorkflows < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(Households::SeedDefaultWorkflows)

    say_with_time "seeding scheduled workflows for existing households" do
      Household.find_each do |household|
        Households::SeedDefaultWorkflows.call(household)
      end
    end
  end

  def down
    Workflow.unscoped.where.not(seed_key: nil).destroy_all
  end
end
