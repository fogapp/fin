# typed: strict

module Transfers
  # One-time historical sweep for the credit-card-payments rollout
  # (docs/credit-card-payments.md §F). Idempotent — every step is a no-op on
  # rows it already processed. Run via bin/rails payments:backfill, then
  # metrics:backfill_all to recompute the stats store under the new scopes.
  class PaymentBackfill
    extend T::Sig

    sig { returns(T::Hash[Symbol, Integer]) }
    def call
      stats = {
        types_normalized: normalize_card_credit_types,
        transfers_classified: classify_existing_transfers,
        candidates_confirmed: confirm_existing_candidates,
        pairs_matched: match_unlinked_rows,
        residual_suspects: report_residual_suspects
      }
      # normalize_card_credit_types writes via update_all, which skips the
      # after_commit bump — rotate the cached-endpoint version once at the end.
      Households::DataVersion.bump!(Current.household&.id)
      stats
    end

    private

    # Card credits Plaid fell back to "Return" on (payment/funding events) —
    # under the old scopes they spuriously subtracted from spend.
    sig { returns(Integer) }
    def normalize_card_credit_types
      CashTransaction
        .source_credit_card
        .where("amount > 0")
        .where.not(transaction_type: CashTransaction::TransactionType::Payment.serialize)
        .where(
          "raw_category LIKE 'LOAN_PAYMENTS%' OR raw_category LIKE 'TRANSFER_IN%' OR description ~* ?",
          PaymentSignals::SIGNATURE_PATTERN.source
        )
        .update_all(transaction_type: CashTransaction::TransactionType::Payment.serialize)
    end

    # Existing transfers predate kind — classify them and apply the treatment
    # defaults (notably: loan-payment pairs become countable spend).
    sig { returns(Integer) }
    def classify_existing_transfers
      count = 0
      Transfer.where(kind: Transfer::Kind::Transfer).find_each do |transfer|
        classification = KindClassifier.classify(transfer)
        next if classification.kind == Transfer::Kind::Transfer

        transfer.update!(kind: classification.kind, include_in_spend: classification.include_in_spend)
        count += 1
      end
      count
    end

    # Unconfirmed candidates from earlier scans that are actually payment
    # pairs with corroborating signals — confirm them (they excluded nothing
    # while unconfirmed).
    sig { returns(Integer) }
    def confirm_existing_candidates
      count = 0
      Transfer.candidates.payments.find_each do |transfer|
        from = transfer.from_transaction
        to   = transfer.to_transaction
        next unless from.is_a?(CashTransaction) && to.is_a?(CashTransaction)
        next unless PaymentSignals.auto_confirmable?(from, to)

        transfer.confirm!(source: Transfer::ConfirmationSource::Auto)
        count += 1
      end
      count
    end

    # Probe every unlinked payment-shaped row (both sides — the matcher
    # pre-filters and each pair links on whichever leg probes first).
    sig { returns(Integer) }
    def match_unlinked_rows
      count = 0
      candidates = CashTransaction.payment_suspects
        .or(
          CashTransaction.source_credit_card
            .where("amount > 0")
            .where(transaction_type: CashTransaction::TransactionType::Payment.serialize)
            .where(transfer_id: nil)
        )

      candidates.find_each do |txn|
        transfer = PaymentMatcher.new(txn).match!
        count += 1 if transfer&.confirmed?
      end
      count
    end

    # Whatever is still counted as spend after matching gets one summary
    # Issue so it lands in the review flow instead of silently persisting.
    sig { returns(Integer) }
    def report_residual_suspects
      suspects = CashTransaction.payment_suspects.order(transaction_date: :desc).to_a
      return 0 if suspects.empty?

      lines = suspects.first(25).map do |t|
        "- #{t.transaction_date} · #{t.account&.name} · #{format('%.2f', t.amount)} · #{t.description&.slice(0, 60)}"
      end
      Issue.create!(
        title:    "#{suspects.size} suspected payment#{suspects.size == 1 ? '' : 's'} still counted as spending",
        body:     "These bank debits look like card/loan payments but have no linked transfer, " \
                  "so they count in spend. Link them (transaction drawer → Link as transfer) or " \
                  "confirm they're real spending.\n\n#{lines.join("\n")}",
        severity: Severity::Warning,
        source:   "payment_backfill"
      )
      suspects.size
    end
  end
end
