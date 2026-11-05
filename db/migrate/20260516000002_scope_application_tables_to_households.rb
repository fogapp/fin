class ScopeApplicationTablesToHouseholds < ActiveRecord::Migration[8.0]
  TABLES = %w[
    accounts brokers categories tags merchants merchant_rules
    rules rule_folders rule_conditions rule_actions rule_executions
    cash_transactions investment_transactions position_snapshots
    transfers csv_imports recurring_patterns saved_views
    plaid_items plaid_accounts
  ].freeze

  def up
    return unless table_exists?(:households)

    # 1. Add nullable household_id to each scoped table.
    TABLES.each do |table|
      next unless table_exists?(table)
      next if connection.column_exists?(table, :household_id)
      add_reference table, :household, type: :uuid, foreign_key: { on_delete: :cascade }, null: true
    end

    # 2. Backfill — assign every existing row to the default household. If no
    #    default household exists yet (a truly fresh DB), create one.
    default_household_id = connection.select_value(
      "SELECT id FROM households ORDER BY created_at ASC LIMIT 1"
    )
    if default_household_id.nil?
      default_household_id = connection.select_value(
        "INSERT INTO households (name, created_at, updated_at) VALUES ('Default', NOW(), NOW()) RETURNING id"
      )
    end

    TABLES.each do |table|
      next unless table_exists?(table)
      connection.execute(
        "UPDATE #{connection.quote_table_name(table)} SET household_id = '#{default_household_id}' WHERE household_id IS NULL"
      )
    end

    # 3. Set NOT NULL and add household-scoped indexes for common access patterns.
    TABLES.each do |table|
      next unless table_exists?(table)
      change_column_null table, :household_id, false
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table)
      remove_reference table, :household, foreign_key: true
    end
  end
end
