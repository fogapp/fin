# Cutover for the subscriptions redesign (docs/subscriptions-redesign.md §9):
# recurring_patterns is replaced by recurring_series + recurring_occurrences.
# Patterns aren't migrated as data — the new detector re-derives everything
# from transaction history on its next run (Plaid sync, CSV import, or the
# nightly job), with the richer cadence model, as reviewable suggestions.
#
# Workflows triggered by recurring_pattern.* events are deactivated (their
# trigger no longer exists); the equivalent triggers are recurring_series.*
# and the subscription.* app events.
class DropRecurringPatterns < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE workflows SET active = false WHERE trigger_type LIKE 'recurring_pattern.%'
    SQL
    drop_table :recurring_patterns
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
