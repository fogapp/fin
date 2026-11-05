# The observability index (docs/workflow_engine_design.md follow-up): one
# row per meaningful operation (sync completed, import finished, workflow
# run, detection pass, error), pointing at the rich domain records rather
# than copying them. trace_id threads a causal episode together — a Plaid
# sync, the workflow runs it fired, and the notifications those produced all
# share one trace.
class CreateActivityEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.datetime :occurred_at, null: false
      t.string :source, null: false   # plaid_sync, import, workflow, api, job, ...
      t.string :event, null: false    # e.g. "sync.completed", "run.failed"
      t.string :severity, null: false, default: "info"
      t.string :summary, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :subject_type
      t.uuid :subject_id
      t.uuid :trace_id
      t.string :caused_by_type
      t.uuid :caused_by_id
      t.integer :duration_ms
      t.timestamps
      t.index %i[household_id occurred_at]
      t.index %i[household_id source occurred_at]
      t.index %i[household_id severity occurred_at]
      t.index :trace_id
      t.index %i[subject_type subject_id]
    end
    add_foreign_key :activity_entries, :households, on_delete: :cascade

    add_column :workflow_runs, :trace_id, :uuid
    add_index  :workflow_runs, :trace_id
    add_column :notifications, :trace_id, :uuid
    add_index  :notifications, :trace_id
  end
end
