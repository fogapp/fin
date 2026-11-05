class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.string  :source_filename, null: false
      t.string  :broker_name
      t.integer :status, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :skipped_count,  null: false, default: 0
      t.integer :error_count,    null: false, default: 0
      t.text    :error_log
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :csv_imports, :created_at
  end
end
