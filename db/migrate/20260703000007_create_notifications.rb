# In-app notifications produced by workflow `notify` actions (and anything
# else that wants a durable user-facing message), plus an optional
# per-household webhook (e.g. ntfy) that notify actions POST to.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.string :title, null: false
      t.text :body
      t.string :severity, null: false, default: "info"
      t.string :subject_type
      t.uuid :subject_id
      t.uuid :workflow_run_id
      t.datetime :read_at
      t.timestamps
      t.index %i[household_id created_at]
      t.index %i[household_id read_at]
    end
    add_foreign_key :notifications, :households, on_delete: :cascade
    add_foreign_key :notifications, :workflow_runs, on_delete: :nullify

    add_column :households, :notification_webhook_url, :string
  end
end
