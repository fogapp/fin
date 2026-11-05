# typed: true

# The link between a Fin datatable and a spreadsheet in Office. One row
# per exported sheet: which dataset it came from, the filters that produced
# it, and the Office document it writes to — which is what makes "Refresh"
# possible instead of piling up a new spreadsheet per export.
class CreateOfficeSheetExports < ActiveRecord::Migration[8.1]
  def change
    create_table :office_sheet_exports, id: :uuid do |t|
      t.uuid :household_id, null: false
      t.uuid :user_id
      # Office::Datasets key: transactions, holdings, portfolio.
      t.string :dataset, null: false
      t.string :title, null: false
      # Office document ids are bigints from another app, not Fin uuids.
      t.bigint :document_id, null: false
      t.string :sheet_name
      t.string :url
      # The dataset params the export was built from, replayed on refresh.
      t.jsonb :filters, null: false, default: {}
      # The extent last written, so a refresh can blank rows that shrank
      # away instead of leaving stale data below the new last row.
      t.integer :row_count, null: false, default: 0
      t.integer :column_count, null: false, default: 0
      t.datetime :last_exported_at
      t.text :last_error
      t.timestamps
    end

    add_index :office_sheet_exports, [ :household_id, :dataset ]
    add_index :office_sheet_exports, [ :household_id, :document_id ], unique: true
    add_foreign_key :office_sheet_exports, :households, on_delete: :cascade
    add_foreign_key :office_sheet_exports, :users, on_delete: :nullify
  end
end
