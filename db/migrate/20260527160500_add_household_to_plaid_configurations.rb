class AddHouseholdToPlaidConfigurations < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:households) && table_exists?(:plaid_configurations)

    # Add household_id column
    add_reference :plaid_configurations, :household, type: :uuid, foreign_key: { on_delete: :cascade }, null: true

    # Backfill with default household
    default_household_id = connection.select_value(
      "SELECT id FROM households ORDER BY created_at ASC LIMIT 1"
    )

    if default_household_id.present?
      connection.execute(
        "UPDATE plaid_configurations SET household_id = '#{default_household_id}' WHERE household_id IS NULL"
      )
    end

    # Make it required
    change_column_null :plaid_configurations, :household_id, false
  end

  def down
    remove_reference :plaid_configurations, :household, foreign_key: true
  end
end
