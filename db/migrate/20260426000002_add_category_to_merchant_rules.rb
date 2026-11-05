class AddCategoryToMerchantRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :merchant_rules, :category, foreign_key: true, null: true
  end
end
