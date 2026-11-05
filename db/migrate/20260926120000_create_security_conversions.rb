class CreateSecurityConversions < ActiveRecord::Migration[8.1]
  def change
    create_table :security_conversions, id: :uuid do |t|
      t.references :household, type: :uuid, null: false, foreign_key: true, index: false
      t.references :from_security, type: :uuid, null: false, foreign_key: { to_table: :securities }
      t.references :to_security, type: :uuid, null: false, foreign_key: { to_table: :securities }
      t.date :effective_date, null: false
      # to_security shares received per from_security share, in each
      # security's current (split-adjusted) units.
      t.decimal :ratio, precision: 20, scale: 10, null: false
      t.string :status, null: false, default: "suggested"
      t.string :source, null: false, default: "detected"
      t.jsonb :evidence, null: false, default: {}
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :security_conversions, %i[household_id from_security_id to_security_id],
              unique: true, name: "index_security_conversions_on_pair"
  end
end
