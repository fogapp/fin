class CreateSavedViews < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_views do |t|
      t.string :name, null: false
      t.text   :filter_params, null: false
      t.timestamps
    end
  end
end
