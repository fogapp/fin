class AddInterestOnlyToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :interest_only, :boolean, null: false, default: false
  end
end
