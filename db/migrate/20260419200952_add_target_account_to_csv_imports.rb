class AddTargetAccountToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_reference :csv_imports, :target_account, null: true,
                  foreign_key: { to_table: :accounts }
  end
end
