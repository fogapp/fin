# typed: true

module Transfers
  # Per-transaction payment probe, enqueued on cash_transaction creation so a
  # payment pair auto-confirms minutes after sync instead of waiting for a
  # manual transfer scan. The window where an unlinked payment leg counts as
  # spend shrinks to the queue latency.
  class PaymentMatchJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { params(transaction_id: String).void }
    def perform(transaction_id)
      with_record(CashTransaction, transaction_id) do |txn|
        PaymentMatcher.new(txn).match!
      end
    end
  end
end
