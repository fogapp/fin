# Transfers redesign (docs/transfers-redesign.md):
#
# - accounts.kind: "standard" (default) | "external". External accounts
#   represent real accounts the system doesn't sync (e.g. an unlinked
#   Schwab) — created with just a name, no broker, no balance.
# - accounts.broker_id becomes nullable to support broker-less external
#   accounts (standard accounts still require one at the model layer).
# - transfers.counterparty_account_id: the "other side" of a one-sided
#   transfer when no matchable counterpart transaction exists.
class AddAccountKindAndTransferCounterparty < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :kind, :string, null: false, default: "standard"
    change_column_null :accounts, :broker_id, true

    add_column :transfers, :counterparty_account_id, :uuid
    add_index :transfers, :counterparty_account_id
    add_foreign_key :transfers, :accounts, column: :counterparty_account_id, on_delete: :nullify
  end
end
