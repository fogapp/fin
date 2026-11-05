# Subscription detection runs as a seeded scheduled workflow (like the sync
# schedules) instead of a recurring.yml cron entry — visible and editable in
# the workflow builder, run-now able, observable in runs. New households get
# it from SeedDefaultWorkflows at creation; this backfills existing ones
# (idempotent via seed_key).
class SeedRecurringDetectionWorkflow < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(Households::SeedDefaultWorkflows)

    Household.find_each { |h| Households::SeedDefaultWorkflows.call(h) }
  end

  def down
    # Seeded workflows are user-editable after creation; leave them in place.
  end
end
