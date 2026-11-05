# typed: true

# Every point on a property's value chart: weekly RentCast AVM estimates,
# values the user types in, the purchase price, recorded deed sales, and
# county tax assessments (charted as a reference line, never counted as
# market value).
#
# The (property, source, as_of) unique index is what makes syncing
# idempotent — two AVM pulls on the same day update one row instead of
# stacking, and re-seeding history from GET /properties is a no-op.
class CreateRealEstateValuations < ActiveRecord::Migration[8.1]
  def change
    create_table :real_estate_valuations, id: :uuid do |t|
      t.uuid :household_id, null: false
      t.uuid :real_estate_property_id, null: false
      t.date :as_of, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :source, null: false
      # RentCast's 85%-confidence band; nil for every other source.
      t.decimal :value_low,  precision: 15, scale: 2
      t.decimal :value_high, precision: 15, scale: 2
      t.jsonb :payload

      t.timestamps
    end

    add_index :real_estate_valuations, [ :real_estate_property_id, :source, :as_of ],
              unique: true, name: "index_real_estate_valuations_unique_point"
    add_index :real_estate_valuations, [ :real_estate_property_id, :as_of ]
    add_index :real_estate_valuations, :household_id
    add_foreign_key :real_estate_valuations, :households, on_delete: :cascade
    add_foreign_key :real_estate_valuations, :real_estate_properties, on_delete: :cascade
  end
end
