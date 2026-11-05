# On-chain transfer quantities carry wei-level precision (18 decimals);
# 6dp rounding breaks exact ledger↔observation reconciliation and the
# symmetry of self-transfer legs.
class WidenQuantityPrecisionForCrypto < ActiveRecord::Migration[8.1]
  def up
    change_column :investment_transactions, :quantity, :decimal, precision: 38, scale: 18
    change_column :position_snapshots, :quantity, :decimal, precision: 38, scale: 18
    add_column :alchemy_wallets, :known_token_contracts, :jsonb, null: false, default: {}
  end

  def down
    change_column :investment_transactions, :quantity, :decimal, precision: 18, scale: 6
    change_column :position_snapshots, :quantity, :decimal, precision: 18, scale: 6
    remove_column :alchemy_wallets, :known_token_contracts
  end
end
