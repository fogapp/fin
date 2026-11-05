class AddExecutingDealerToInvestmentTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :investment_transactions, :executing_dealer, :string
    add_index :investment_transactions, :executing_dealer
  end
end
