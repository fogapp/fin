# typed: false

# A row that can sit on either side of a Transfer (CashTransaction,
# InvestmentTransaction). Destroying a leg dissolves every Transfer that
# references it — otherwise a Plaid `removed` event (or a manual delete) for
# one leg of a confirmed transfer leaves the surviving leg permanently
# excluded from spend/income. Transfer#destroy! runs unlink_transactions,
# which clears the other leg's transfer_id.
#
# Include this before any `dependent:` associations so the before_destroy
# runs ahead of their cleanup.
module TransferLeg
  extend ActiveSupport::Concern

  included do
    belongs_to :transfer, optional: true
    before_destroy :dissolve_transfers
  end

  private

  # unscoped + explicit household filter: background destroys (Plaid sync
  # jobs, console cleanups) may run without Current.household set, and the
  # default scope would silently miss the referencing transfers.
  def dissolve_transfers
    Transfer.unscoped
            .where(household_id: household_id)
            .referencing(self)
            .find_each { |transfer| transfer.destroy! }
  end
end
