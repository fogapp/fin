class CreatePlaidItems < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_items do |t|
      t.string  :item_id,           null: false
      t.text    :access_token,      null: false
      t.string  :institution_id
      t.string  :institution_name
      t.text    :cursor
      t.string  :status,            null: false, default: "active"
      t.text    :error_message
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :plaid_items, :item_id, unique: true
  end
end
