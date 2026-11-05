class AddMerchantToLoans < ActiveRecord::Migration[8.1]
  def change
    add_reference :loans, :merchant, null: true, foreign_key: true, type: :uuid
  end
end
