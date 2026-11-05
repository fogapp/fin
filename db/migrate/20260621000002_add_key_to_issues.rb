class AddKeyToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :key, :string

    # Unique per household — same condition can't create duplicate open issues
    add_index :issues, [ :household_id, :key ],
              unique: true,
              where: "key IS NOT NULL",
              name: "index_issues_on_household_id_and_key"
  end
end
