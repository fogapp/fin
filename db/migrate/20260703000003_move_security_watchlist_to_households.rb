# securities.watched was a flag on the globally shared securities table, so
# one household's watchlist was every household's watchlist. Replace it with
# a per-household join table.
class MoveSecurityWatchlistToHouseholds < ActiveRecord::Migration[8.1]
  def up
    create_table :security_watches, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.uuid :security_id, null: false
      t.timestamps
      t.index %i[household_id security_id], unique: true
      t.index :security_id
    end
    add_foreign_key :security_watches, :households, on_delete: :cascade
    add_foreign_key :security_watches, :securities, on_delete: :cascade

    # Preserve current behavior: every household keeps seeing the securities
    # that were globally watched.
    execute <<~SQL
      INSERT INTO security_watches (id, household_id, security_id, created_at, updated_at)
      SELECT gen_random_uuid(), h.id, s.id, NOW(), NOW()
      FROM households h CROSS JOIN securities s
      WHERE s.watched = TRUE
    SQL

    remove_column :securities, :watched
  end

  def down
    add_column :securities, :watched, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE securities SET watched = TRUE
      WHERE id IN (SELECT DISTINCT security_id FROM security_watches)
    SQL
    drop_table :security_watches
  end
end
