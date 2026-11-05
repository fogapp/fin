# The DB enforced globally-unique tag and category names while the models
# validate uniqueness per household — the first cross-household name
# collision raises RecordNotUnique (500) and leaks that the name exists in
# another tenant. Align the indexes with the model validations.
class ScopeTagAndCategoryUniquenessToHousehold < ActiveRecord::Migration[8.1]
  def up
    remove_index :tags, name: "index_tags_on_name"
    # Tag validates uniqueness case-insensitively.
    add_index :tags, "household_id, lower(name)",
              unique: true, name: "index_tags_on_household_id_and_lower_name"

    remove_index :categories, name: "index_categories_on_name"
    # Category uniqueness is scoped to [household_id, parent_id]; parent_id
    # is NULL for roots, and Postgres treats NULLs as distinct in unique
    # indexes, so roots need their own partial index.
    add_index :categories, %i[household_id parent_id name],
              unique: true, where: "parent_id IS NOT NULL",
              name: "index_categories_on_household_parent_name"
    add_index :categories, %i[household_id name],
              unique: true, where: "parent_id IS NULL",
              name: "index_categories_on_household_name_roots"
  end

  def down
    remove_index :tags, name: "index_tags_on_household_id_and_lower_name"
    add_index :tags, :name, unique: true

    remove_index :categories, name: "index_categories_on_household_parent_name"
    remove_index :categories, name: "index_categories_on_household_name_roots"
    add_index :categories, :name, unique: true
  end
end
