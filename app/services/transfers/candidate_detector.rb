# typed: strict

module Transfers
  # Turns TransferCandidateService's matched pairs into Transfer candidates
  # for the current household: skips pairs the user dismissed or whose legs
  # already sit in a transfer, classifies the kind, auto-confirms payments
  # with corroborating signals, and clears candidates that have gone stale.
  # Returns how many candidates it created.
  class CandidateDetector
    extend T::Sig

    sig { returns(Integer) }
    def call
      # Pairs the user has rejected stay rejected — orientation-insensitive.
      dismissed_pairs = TransferDismissal
        .pluck(:from_transaction_id, :to_transaction_id)
        .map(&:sort).to_set
      # Loaded once instead of two exists? per side per candidate; kept
      # current as candidates are created so a later pair can't reuse a leg.
      linked = Transfer.linked_sides

      created = T.let(0, Integer)
      TransferCandidateService.new.candidates.each do |r|
        from_side = [ r.from_type, r.from_transaction.id ]
        to_side   = [ r.to_type, r.to_transaction.id ]
        next if dismissed_pairs.include?([ r.from_transaction.id, r.to_transaction.id ].sort)
        next if linked.include?(from_side) || linked.include?(to_side)

        create_candidate(r)
        linked << from_side << to_side
        created += 1
      rescue ActiveRecord::RecordNotUnique
        # Race condition or duplicate — safe to skip
      rescue ActiveRecord::RecordInvalid => e
        # One bad pair must not abort the whole household run (the cleanup pass
        # and activity summary below still need to happen) — log and move on.
        Rails.logger.warn(
          "[Transfers::CandidateDetector] skipped candidate " \
          "#{r.from_type}:#{r.from_transaction.id} → #{r.to_type}:#{r.to_transaction.id}: #{e.message}"
        )
      end

      # Found in one query; destroyed one by one so the deleted-event and
      # data-version callbacks still fire (stale candidates are rare).
      Transfer.stale_candidates.find_each(&:destroy!)

      if created.positive?
        Activity.record(
          source: "transfer_detection", event: "detection.completed",
          summary: "Transfer detection: #{created} new candidate#{created == 1 ? '' : 's'}",
          payload: { created: created }
        )
      end

      created
    end

    private

    sig { params(r: TransferCandidateService::Result).void }
    def create_candidate(r)
      classification = KindClassifier.new(from: r.from_transaction, to: r.to_transaction).classify

      candidate = Transfer.create!(
        from_transaction_id:   r.from_transaction.id,
        from_transaction_type: r.from_type,
        to_transaction_id:     r.to_transaction.id,
        to_transaction_type:   r.to_type,
        amount:                r.amount,
        kind:                  classification.kind,
        include_in_spend:      classification.include_in_spend
      )

      # Payment pairs with corroborating signals skip the review queue —
      # the structural anchor (a credit into the household's own card/loan
      # account) rules out the payments-to-other-people failure mode.
      if candidate.payment? &&
         r.from_transaction.is_a?(CashTransaction) && r.to_transaction.is_a?(CashTransaction) &&
         PaymentSignals.auto_confirmable?(r.from_transaction, r.to_transaction)
        candidate.confirm!(source: Transfer::ConfirmationSource::Auto)
        Workflows::Events.publish("transfer.auto_confirmed", subject: candidate,
                                  payload: { "kind" => candidate.kind.serialize, "amount" => r.amount.to_s })
      else
        event = candidate.payment? ? "transfer.payment_detected" : "transfer.candidate_detected"
        Workflows::Events.publish(event, subject: candidate,
                                  payload: { "amount" => r.amount.to_s })
      end
    end
  end
end
