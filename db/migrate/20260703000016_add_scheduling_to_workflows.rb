# Schedule triggers for workflows: next_scheduled_at drives the tick job's
# due query; seed_key identifies the default workflows seeded per household
# (idempotent re-seeding + stable UI lookup).
class AddSchedulingToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :next_scheduled_at, :datetime
    add_column :workflows, :seed_key, :string
    add_index :workflows, %i[household_id seed_key], unique: true, where: "seed_key IS NOT NULL"
    add_index :workflows, :next_scheduled_at, where: "next_scheduled_at IS NOT NULL"
  end
end
