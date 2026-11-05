class CreateSavedReports < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_reports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.string :name, null: false
      t.text :config, null: false
      t.timestamps
      t.index :household_id
    end
  end
end
