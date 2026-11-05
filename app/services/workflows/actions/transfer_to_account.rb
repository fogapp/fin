# typed: strict

module Workflows
  module Actions
    # The parameterized sibling of MarkAsTransfer: "this transaction is a
    # transfer to/from <account>". Tries the standard counterpart match
    # restricted to the target account first (best case: a confirmed pair);
    # when no unique counterpart exists it creates a confirmed one-sided
    # transfer with counterparty_account_id, so exclusion still works even
    # when the other side is untracked (external account, CSV gap).
    class TransferToAccount < T::Struct
      TOLERANCE = T.let(Transfer::AMOUNT_TOLERANCE, Numeric)
      DAYS      = T.let(Transfer::CANDIDATE_DAYS, Integer)

      const :account_id, T.nilable(String)

      sig { params(resource: T.untyped, dry_run: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def execute(resource, dry_run: false)
        return { status: :skipped, reason: "already linked to a transfer" } if resource.transfer_id.present?

        account = ::Account.unscoped.where(household_id: resource.household_id).find_by(id: account_id)
        return { status: :error, error: "account #{account_id} not found" } unless account
        return { status: :skipped, reason: "transaction is already in the target account" } if resource.account_id == account.id

        counterparts = find_counterparts(resource, account)

        if counterparts.size == 1
          counterpart = T.must(counterparts.first)
          return { status: :applied, dry_run: true, counterpart_id: counterpart.id } if dry_run

          transfer = create_pair(resource, counterpart)
          { status: :applied, transfer_id: transfer.id, counterpart_id: counterpart.id }
        else
          return { status: :applied, dry_run: true, counterparty_account_id: account.id } if dry_run

          transfer = create_one_sided(resource, account)
          { status: :applied, transfer_id: transfer.id, counterparty_account_id: account.id }
        end
      end

      private

      sig { params(resource: T.untyped, counterpart: T.untyped).returns(Transfer) }
      def create_pair(resource, counterpart)
        transfer = Transfer.create!(
          household_id:          resource.household_id,
          amount:                resource.amount.abs,
          from_transaction_id:   resource.amount < 0 ? resource.id : counterpart.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     resource.amount < 0 ? counterpart.id : resource.id,
          to_transaction_type:   "CashTransaction"
        )
        classify_and_confirm(transfer)
      end

      # Negative amount = money leaving the resource's account (from side,
      # transfer *to* the counterparty); positive = the reverse.
      sig { params(resource: T.untyped, account: T.untyped).returns(Transfer) }
      def create_one_sided(resource, account)
        side = resource.amount < 0 ? :from : :to
        transfer = Transfer.create!(
          household_id:             resource.household_id,
          amount:                   resource.amount.abs,
          counterparty_account_id:  account.id,
          "#{side}_transaction_id":   resource.id,
          "#{side}_transaction_type": "CashTransaction"
        )
        classify_and_confirm(transfer)
      end

      sig { params(transfer: Transfer).returns(Transfer) }
      def classify_and_confirm(transfer)
        classification = Transfers::KindClassifier.classify(transfer)
        transfer.update!(kind: classification.kind, include_in_spend: classification.include_in_spend)
        transfer.confirm!(source: Transfer::ConfirmationSource::Workflow)
        transfer
      end

      # Same window/tolerance as MarkAsTransfer, but restricted to the target
      # account. Limit 2: we only need to distinguish "exactly one" from
      # "none or ambiguous".
      sig { params(txn: T.untyped, account: T.untyped).returns(T::Array[CashTransaction]) }
      def find_counterparts(txn, account)
        CashTransaction
          .where.not(id: txn.id)
          .where(account_id: account.id)
          .where(transfer_id: nil)
          .where("ABS(amount + ?) < ?", txn.amount, TOLERANCE)
          .where("ABS(transaction_date::date - ?::date) <= ?", txn.transaction_date, DAYS)
          .limit(2)
          .to_a
      end
    end
  end
end
