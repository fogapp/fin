# typed: true

# A household's own name for a (globally shared) security, so holdings whose
# ticker is missing or whose custodian description is noise can be given a
# readable label. Per household for the same reason watchlists are.
class CreateSecurityLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :security_labels, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :household_id, null: false
      t.uuid   :security_id,  null: false
      t.string :label,        null: false
      t.timestamps
      t.index %i[household_id security_id], unique: true
      t.index :security_id
    end
    add_foreign_key :security_labels, :households, on_delete: :cascade
    add_foreign_key :security_labels, :securities, on_delete: :cascade
  end
end
