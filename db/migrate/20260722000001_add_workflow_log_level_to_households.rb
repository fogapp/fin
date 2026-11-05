# typed: true

class AddWorkflowLogLevelToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :workflow_log_level, :string, null: false, default: "info"
  end
end
