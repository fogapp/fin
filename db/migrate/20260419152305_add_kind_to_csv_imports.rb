class AddKindToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :kind, :integer, null: false, default: 0
    add_index  :csv_imports, :kind
  end
end
