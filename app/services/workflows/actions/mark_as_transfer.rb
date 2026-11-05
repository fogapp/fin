# typed: strict

module Workflows
  module Actions
    class MarkAsTransfer < T::Struct
      TOLERANCE = T.let(Transfer::AMOUNT_TOLERANCE, Numeric)
      DAYS      = T.let(Transfer::CANDIDATE_DAYS, Integer)

      sig { params(resource: T.untyped, dry_run: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def execute(resource, dry_run: false)
        return { status: :skipped, reason: "already linked to a transfer" } if resource.transfer_id.present?

        counterparts = find_counterparts(resource)

        if counterparts.empty?
          return { status: :skipped, reason: "no offsetting counterpart found" }
        end

        if counterparts.size > 1
          return { status: :skipped, reason: "#{counterparts.size} ambiguous counterparts found — add more conditions to narrow the match" }
        end

        counterpart = T.must(counterparts.first)

        return { status: :applied, dry_run: true, counterpart_id: counterpart.id } if dry_run

        transfer = Transfer.create!(
          amount:               resource.amount.abs,
          from_transaction_id:  resource.amount < 0 ? resource.id : counterpart.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:    resource.amount < 0 ? counterpart.id : resource.id,
          to_transaction_type:  "CashTransaction"
        )
        classification = Transfers::KindClassifier.classify(transfer)
        transfer.update!(kind: classification.kind, include_in_spend: classification.include_in_spend)
        transfer.confirm!(source: Transfer::ConfirmationSource::Workflow)

        { status: :applied, transfer_id: transfer.id, counterpart_id: counterpart.id }
      end

      private

      sig { params(txn: CashTransaction).returns(T::Array[CashTransaction]) }
      def find_counterparts(txn)
        CashTransaction
          .where.not(id: txn.id)
          .where.not(account_id: txn.account_id)
          .where(transfer_id: nil)
          .where("ABS(amount + ?) < ?", txn.amount, TOLERANCE)
          .where("ABS(transaction_date::date - ?::date) <= ?", txn.transaction_date, DAYS)
          .to_a
      end
    end
  end
end
