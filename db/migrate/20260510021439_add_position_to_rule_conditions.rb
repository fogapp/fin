class AddPositionToRuleConditions < ActiveRecord::Migration[8.1]
  def change
    add_column :rule_conditions, :position, :integer, null: false, default: 0
    add_index  :rule_conditions, [ :rule_id, :position ]
  end
end
