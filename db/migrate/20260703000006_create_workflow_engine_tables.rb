# Core tables for the workflow engine (docs/workflow_engine_design.md):
# workflows own a tree of steps; each triggering event produces a run with
# per-step outcomes as the durable audit trail.
class CreateWorkflowEngineTables < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :trigger_type, null: false
      t.jsonb :trigger_config, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[household_id trigger_type active]
      t.index %i[household_id name], unique: true
    end
    add_foreign_key :workflows, :households, on_delete: :cascade

    create_table :workflow_steps, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_id, null: false
      t.uuid :parent_id
      t.integer :position, null: false, default: 0
      t.string :kind, null: false # branch | action | wait
      t.jsonb :config, null: false, default: {}
      t.timestamps
      t.index %i[workflow_id parent_id position]
    end
    add_foreign_key :workflow_steps, :workflows, on_delete: :cascade
    add_foreign_key :workflow_steps, :workflow_steps, column: :parent_id, on_delete: :cascade

    create_table :workflow_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_id, null: false
      t.uuid :household_id, null: false
      t.string :subject_type
      t.uuid :subject_id
      t.string :event_type, null: false
      t.jsonb :event_payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.uuid :cursor_step_id
      t.uuid :triggered_by_run_id
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index %i[workflow_id created_at]
      t.index %i[household_id created_at]
      t.index %i[subject_type subject_id]
      t.index :status
      t.index :triggered_by_run_id
    end
    add_foreign_key :workflow_runs, :workflows, on_delete: :cascade
    add_foreign_key :workflow_runs, :households, on_delete: :cascade

    create_table :workflow_run_steps, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_run_id, null: false
      t.uuid :workflow_step_id
      t.string :status, null: false
      t.jsonb :output, null: false, default: {}
      t.datetime :resume_at
      t.timestamps
      t.index %i[workflow_run_id created_at]
    end
    add_foreign_key :workflow_run_steps, :workflow_runs, on_delete: :cascade
    # Steps can be edited or deleted while historical runs exist.
    add_foreign_key :workflow_run_steps, :workflow_steps, on_delete: :nullify
  end
end
