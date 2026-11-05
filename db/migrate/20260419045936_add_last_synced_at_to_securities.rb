class AddLastSyncedAtToSecurities < ActiveRecord::Migration[8.1]
  def change
    add_column :securities, :last_synced_at, :datetime
  end
end
