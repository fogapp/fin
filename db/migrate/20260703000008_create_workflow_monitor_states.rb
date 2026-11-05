# Edge-trigger state for monitor workflows: a run fires only when a
# subject's condition result transitions false→true, so a balance sitting
# below its threshold doesn't re-notify on every evaluation.
class CreateWorkflowMonitorStates < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_monitor_states, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_id, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.boolean :result, null: false, default: false
      t.datetime :last_evaluated_at
      t.timestamps
      t.index %i[workflow_id subject_type subject_id], unique: true,
              name: "index_monitor_states_on_workflow_and_subject"
    end
    add_foreign_key :workflow_monitor_states, :workflows, on_delete: :cascade
  end
end
