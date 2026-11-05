# Budgeting (docs: flex-bucket budgets modeled on the current state of the
# art — Monarch's fixed/flex/non-monthly buckets and rollover math, YNAB's
# zero-based left-to-plan, Copilot's history-driven suggestions).
#
# - categories.budget_kind buckets every category (flex default)
# - budget_periods: one row per (household, month) for period-level fields
# - budget_lines: planned amount per (household, category, month) with
#   opt-in rollover and edge stamps for threshold workflow events
class CreateBudgeting < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :budget_kind, :string, null: false, default: "flex"

    create_table :budget_periods, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.date :month, null: false # always the first of the month
      t.decimal :income_planned, precision: 14, scale: 2
      t.timestamps
      t.index %i[household_id month], unique: true
    end
    add_foreign_key :budget_periods, :households, on_delete: :cascade

    create_table :budget_lines, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.uuid :category_id, null: false
      t.date :month, null: false
      t.decimal :planned, precision: 14, scale: 2, null: false, default: 0
      t.boolean :rollover, null: false, default: false
      # Edge stamps so threshold events fire once per month per level
      t.datetime :approaching_alerted_at
      t.datetime :exceeded_alerted_at
      t.timestamps
      t.index %i[household_id category_id month], unique: true
      t.index %i[household_id month]
    end
    add_foreign_key :budget_lines, :households, on_delete: :cascade
    add_foreign_key :budget_lines, :categories, on_delete: :cascade
  end
end
