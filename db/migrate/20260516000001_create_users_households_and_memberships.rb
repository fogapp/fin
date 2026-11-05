class CreateUsersHouseholdsAndMemberships < ActiveRecord::Migration[8.0]
  def up
    # citext for case-insensitive email uniqueness
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :households, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.citext :email, null: false
      t.string :name
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :household_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user,      type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :household, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :household_memberships, [ :user_id, :household_id ], unique: true

    # api_tokens get scoped to (user, household). Nullable initially so the
    # backfill below can attach the existing dev token without violating NOT NULL.
    add_reference :api_tokens, :user,      type: :uuid, foreign_key: { on_delete: :cascade }
    add_reference :api_tokens, :household, type: :uuid, foreign_key: { on_delete: :cascade }

    # Backfill: every existing api_token gets attached to a single default
    # user + household. Production deploys had no tokens; this only affects
    # the dev seed token.
    if connection.select_value("SELECT COUNT(*) FROM api_tokens").to_i > 0
      household_id = connection.select_value(
        "INSERT INTO households (name, created_at, updated_at) VALUES ('Default', NOW(), NOW()) RETURNING id"
      )
      user_id = connection.select_value(
        "INSERT INTO users (email, name, created_at, updated_at) VALUES ('dev@fin.local', 'Default User', NOW(), NOW()) RETURNING id"
      )
      connection.execute(<<~SQL)
        INSERT INTO household_memberships (user_id, household_id, role, created_at, updated_at)
        VALUES ('#{user_id}', '#{household_id}', 'admin', NOW(), NOW())
      SQL
      connection.execute(<<~SQL)
        UPDATE api_tokens SET user_id = '#{user_id}', household_id = '#{household_id}'
      SQL
    end

    change_column_null :api_tokens, :user_id,      false
    change_column_null :api_tokens, :household_id, false
  end

  def down
    remove_reference :api_tokens, :household, foreign_key: true
    remove_reference :api_tokens, :user,      foreign_key: true
    drop_table :household_memberships
    drop_table :users
    drop_table :households
  end
end
