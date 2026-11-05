class AddRevertedAtToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_runs, :reverted_at, :datetime
  end
end
