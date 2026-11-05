# typed: strict

module Transfers
  # A user-drawn link between two legs ("Mark as transfer", "Mark as credit
  # card payment"). Classified like auto-detection and the workflow actions
  # are, so a manual link gets the same kind/treatment a matching
  # auto-detected pair would have; callers may still override either value
  # explicitly (e.g. forcing credit_card_payment when the counterparty
  # account isn't typed "Credit Card" and the classifier can't infer it
  # structurally).
  #
  # Everything happens in one transaction: saving the link, clearing a past
  # dismissal of the pair, and confirming or back-pointing the legs. A
  # failure part-way used to leave a saved, unconfirmed transfer with the
  # dismissal already gone.
  class ManualLink
    extend T::Sig

    sig { params(attrs: T::Hash[T.untyped, T.untyped], auto_confirm: T::Boolean).returns(Transfer) }
    def self.call(attrs, auto_confirm:)
      new(attrs, auto_confirm: auto_confirm).call
    end

    sig { params(attrs: T::Hash[T.untyped, T.untyped], auto_confirm: T::Boolean).void }
    def initialize(attrs, auto_confirm:)
      @attrs = T.let(attrs.with_indifferent_access, ActiveSupport::HashWithIndifferentAccess)
      @auto_confirm = auto_confirm
    end

    sig { returns(Transfer) }
    def call
      transfer = Transfer.new(@attrs.except(:kind, :include_in_spend))
      classification = KindClassifier.classify(transfer)
      transfer.kind = @attrs[:kind].presence || classification.kind
      transfer.include_in_spend =
        @attrs.key?(:include_in_spend) ? @attrs[:include_in_spend] : classification.include_in_spend

      ActiveRecord::Base.transaction do
        transfer.save!
        # An explicit manual link outranks a past dismissal of the same pair
        # — clear it so unlinking later lets detection suggest the pair again.
        if transfer.from_transaction_id && transfer.to_transaction_id
          TransferDismissal.for_pair(transfer.from_transaction_id, transfer.to_transaction_id).destroy_all
        end
        @auto_confirm ? transfer.confirm! : transfer.sync_transfer_ids
      end
      transfer
    end
  end
end
