class CreateRuleExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_executions do |t|
      t.integer :rule_id                              # nullable — rule may be deleted
      t.string  :trigger_resource,    null: false
      t.integer :trigger_resource_id, null: false
      t.string  :trigger_event,       null: false
      t.string  :status,              null: false
      t.boolean :dry_run,             null: false, default: false
      t.jsonb   :conditions_result
      t.jsonb   :actions_result
      t.text    :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :triggered_by_execution_id            # fk for chain tracking
      t.timestamps
    end

    add_index :rule_executions, :rule_id
    add_index :rule_executions, [ :trigger_resource, :trigger_resource_id ]
    add_index :rule_executions, :status
    add_index :rule_executions, :triggered_by_execution_id
    add_index :rule_executions, :dry_run
  end
end
