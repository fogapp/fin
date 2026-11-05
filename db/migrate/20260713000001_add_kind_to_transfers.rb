# Credit card payments as first-class transfers (docs/credit-card-payments.md):
#
# - transfers.kind: "transfer" (generic, default) | "credit_card_payment" |
#   "loan_payment". Classified from the legs' account types, never asked of
#   the user.
# - transfers.confirmation_source: "user" | "auto" | "workflow" — provenance
#   for confirmed transfers, so auto-matched payments are distinguishable and
#   unlinkable with confidence.
# - transfers.include_in_spend: treatment flag. When true, the OUTFLOW leg
#   still counts in spend_like (cash-basis proxy for payments to untracked
#   cards, budgetable loan payments); inflow legs of linked transfers are
#   always excluded from income.
class AddKindToTransfers < ActiveRecord::Migration[8.1]
  def change
    add_column :transfers, :kind, :string, null: false, default: "transfer"
    add_column :transfers, :confirmation_source, :string
    add_column :transfers, :include_in_spend, :boolean, null: false, default: false
    add_index :transfers, :kind

    reversible do |dir|
      dir.up do
        # Existing confirmed transfers were all confirmed by a person (either
        # directly or via a workflow they authored) before provenance existed.
        execute <<~SQL
          UPDATE transfers SET confirmation_source = 'user' WHERE confirmed_at IS NOT NULL
        SQL
      end
    end
  end
end
