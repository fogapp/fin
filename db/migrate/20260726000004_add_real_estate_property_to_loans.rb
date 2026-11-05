# typed: true

# A mortgage points at the property it finances, so the real estate section
# can show equity and LTV. Net-worth math is unaffected: the loan stays a
# liability in its own bucket and the property is a gross asset in its own,
# so the link is display-only and nothing double-counts.
class AddRealEstatePropertyToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :real_estate_property_id, :uuid
    add_index :loans, :real_estate_property_id
    add_foreign_key :loans, :real_estate_properties, on_delete: :nullify
  end
end
