class AddHrefToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :href, :string
  end
end
