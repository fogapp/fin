# The rules engine is fully superseded: all rules were converted to
# workflows (20260703000009) and deactivated, the endpoints and UI have been
# removed, and old backups' rules restore as workflows. Drop the tables.
class DropLegacyRulesEngineTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :rule_executions, if_exists: true
    drop_table :rule_conditions, if_exists: true
    drop_table :rule_actions, if_exists: true
    drop_table :rules, if_exists: true
    drop_table :rule_folders, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the rules engine was migrated to workflows"
  end
end
