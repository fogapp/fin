class CreateUserPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
  end
end
