class CreateRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rules do |t|
      t.string  :name
      t.text    :description
      t.string  :trigger_resource, null: false
      t.string  :trigger_event,    null: false, default: "any"
      t.boolean :match_all,        null: false, default: true
      t.integer :priority,         null: false, default: 0
      t.boolean :active,           null: false, default: true
      t.boolean :stop_on_failure,  null: false, default: false
      t.timestamps
    end

    add_index :rules, [ :trigger_resource, :trigger_event, :active, :priority ],
              name: "index_rules_on_trigger_and_priority"
  end
end
