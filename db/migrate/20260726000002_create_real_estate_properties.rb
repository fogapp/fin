# typed: true

# Real estate as a tracked asset class. A property carries the address, a
# cache of the facts RentCast reports about it, and the purchase details the
# user enters; its value over time lives in real_estate_valuations.
class CreateRealEstateProperties < ActiveRecord::Migration[8.1]
  def change
    create_table :real_estate_properties, id: :uuid do |t|
      t.uuid :household_id, null: false
      t.string :name, null: false

      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :zip_code
      # RentCast's canonical rendering of the address, plus the slug it uses
      # as a record id. Both are nil until a lookup succeeds.
      t.string :formatted_address
      t.string :rentcast_id
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      # Facts cache — refreshed from GET /properties, never authoritative.
      t.string  :property_type
      t.integer :bedrooms
      t.decimal :bathrooms, precision: 4, scale: 1
      t.integer :square_footage
      t.integer :lot_size
      t.integer :year_built
      t.decimal :hoa_fee, precision: 15, scale: 2

      t.date    :purchase_date
      t.decimal :purchase_price, precision: 15, scale: 2

      # "sold" freezes the property out of net worth from sold_date forward
      # while keeping its value history intact (deleting would discard it).
      t.string  :status, null: false, default: "owned"
      t.date    :sold_date
      t.decimal :sold_price, precision: 15, scale: 2

      # False for addresses RentCast can't resolve — those stay manual-only
      # and are skipped by the weekly fan-out so they don't burn quota.
      t.boolean  :sync_enabled, null: false, default: true
      t.text     :notes
      t.datetime :facts_synced_at
      t.datetime :last_synced_at
      t.string   :last_sync_error

      t.timestamps
    end

    add_index :real_estate_properties, :household_id
    add_index :real_estate_properties, [ :household_id, :status ]
    add_foreign_key :real_estate_properties, :households, on_delete: :cascade
  end
end
