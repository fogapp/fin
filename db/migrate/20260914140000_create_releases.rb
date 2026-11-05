class CreateReleases < ActiveRecord::Migration[8.1]
  def change
    create_table :releases, id: :uuid do |t|
      t.string :git_sha, null: false
      t.timestamps
    end
    add_index :releases, :git_sha, unique: true
  end
end
