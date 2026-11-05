# typed: strict

module Transfers
  # Rejecting a detected candidate must stick: record the pair so detection
  # never re-suggests it, then drop the unconfirmed Transfer row — in one
  # transaction, so a failed destroy can't leave a dismissal behind for a
  # candidate that is still showing. (Plain destroy remains the "unlink"
  # path for confirmed transfers.)
  class Dismiss
    extend T::Sig

    class ConfirmedTransfer < StandardError; end

    sig { params(transfer: Transfer).void }
    def self.call(transfer)
      raise ConfirmedTransfer, "Cannot dismiss a confirmed transfer" if transfer.confirmed?

      ActiveRecord::Base.transaction do
        from_id = transfer.from_transaction_id
        to_id   = transfer.to_transaction_id
        TransferDismissal.record_for!(transfer) if from_id && to_id && TransferDismissal.for_pair(from_id, to_id).none?
        transfer.destroy!
      end
    end
  end
end
