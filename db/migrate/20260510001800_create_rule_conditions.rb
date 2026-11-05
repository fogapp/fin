class CreateRuleConditions < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_conditions do |t|
      t.references :rule, null: false, foreign_key: true
      t.string :field,    null: false
      t.string :operator, null: false
      t.string :value
      t.timestamps
    end
  end
end
