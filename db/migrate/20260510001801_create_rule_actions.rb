class CreateRuleActions < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_actions do |t|
      t.references :rule, null: false, foreign_key: true
      t.string  :action_type,     null: false
      t.jsonb   :params,          null: false, default: {}
      t.integer :position,        null: false, default: 0
      t.boolean :stop_on_failure, null: false, default: false
      t.timestamps
    end

    add_index :rule_actions, [ :rule_id, :position ]
  end
end
