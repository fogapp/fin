class CreateRuleFoldersAndAddPositionToRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_folders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :name,     null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_column :rules, :folder_id, :uuid
    add_column :rules, :position,  :integer, null: false, default: 0

    add_index :rules, [ :folder_id, :position ]
    add_foreign_key :rules, :rule_folders, column: :folder_id, on_delete: :nullify
  end
end
