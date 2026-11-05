class CreateIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :issues, id: :uuid do |t|
      t.uuid   :household_id, null: false
      t.string :title,        null: false
      t.text   :body
      t.string :severity,     null: false, default: "warning"
      t.string :source
      t.datetime :dismissed_at

      t.timestamps
    end

    add_index :issues, :household_id
    add_index :issues, :created_at
    add_foreign_key :issues, :households, on_delete: :cascade
  end
end
