# typed: strict

module Transfers
  # Event-driven payment detection: probes a single cash transaction for a
  # payment-shaped counterpart the moment it lands (docs/credit-card-payments.md §B).
  #
  # The structural anchor (S1) unique to card payments — a positive leg in a
  # Credit Card account funded by a depository debit — cannot occur for
  # payments to other people, so a structural match corroborated by any of
  # S2/S3/S4 (PaymentSignals) is auto-confirmed. Structure alone (the only
  # false-positive shape is a card refund coinciding with an equal unrelated
  # bank debit) becomes an unconfirmed candidate for the review queue.
  #
  # Also upgrades an open one-sided payment into a pair when the late leg
  # arrives (bank side usually posts a day or two after the card side).
  #
  # When no counterpart exists at all — the other side lives in an account
  # Fin doesn't sync — a payment-shaped leg inherits the one-sided link an
  # earlier occurrence of the same payment was given (S5, cadence for
  # untracked counterparties). The stand-in still upgrades to a pair if the
  # missing leg ever shows up.
  class PaymentMatcher
    extend T::Sig

    TOLERANCE = T.let(Transfer::AMOUNT_TOLERANCE, Numeric)
    DAYS      = T.let(Transfer::PAYMENT_CANDIDATE_DAYS, Integer)

    sig { params(txn: CashTransaction).void }
    def initialize(txn)
      @txn = txn
    end

    sig { returns(T.nilable(Transfer)) }
    def match!
      return nil if @txn.transfer_id.present? || Transfer.involving("CashTransaction", @txn.id).exists?
      return nil unless relevant?

      upgrade_one_sided || pair_with_counterpart
    end

    private

    # Cheap pre-filter so the per-row job exits fast for ordinary activity.
    # Card credits and bank debits are the only legs a payment can present.
    sig { returns(T::Boolean) }
    def relevant?
      (card_inflow?(@txn) || bank_outflow?(@txn)) && @txn.amount.to_f.abs >= 0.01
    end

    sig { returns(T.nilable(Transfer)) }
    def pair_with_counterpart
      counterparts = find_counterparts
      # 0 → nothing to pair yet (the probe re-runs when the late leg arrives),
      #     unless an earlier occurrence taught us the counterparty (S5).
      # >1 → ambiguous; the review-queue scan handles it generically rather
      # than guessing between identical amounts.
      return replay_one_sided if counterparts.empty?
      return nil if counterparts.size > 1

      counterpart = T.must(counterparts.first)
      from, to = @txn.amount.to_f.negative? ? [ @txn, counterpart ] : [ counterpart, @txn ]

      classification = KindClassifier.new(from: from, to: to).classify
      return nil if classification.kind == Transfer::Kind::Transfer

      transfer = Transfer.create!(
        household_id:          @txn.household_id,
        amount:                @txn.amount.abs,
        kind:                  classification.kind,
        include_in_spend:      classification.include_in_spend,
        from_transaction_id:   from.id,
        from_transaction_type: "CashTransaction",
        to_transaction_id:     to.id,
        to_transaction_type:   "CashTransaction"
      )

      if PaymentSignals.auto_confirmable?(from, to)
        transfer.confirm!(source: Transfer::ConfirmationSource::Auto)
        Workflows::Events.publish("transfer.auto_confirmed", subject: transfer,
                                  payload: { "kind" => transfer.kind.serialize, "amount" => transfer.amount.to_s })
      else
        Workflows::Events.publish("transfer.payment_detected", subject: transfer,
                                  payload: { "kind" => transfer.kind.serialize, "amount" => transfer.amount.to_s })
      end
      transfer
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent probe (the counterpart's own job) linked one of the legs
      # first — the pair exists, nothing to do.
      nil
    end

    # A one-sided payment whose counterparty is this transaction's account and
    # whose amount/window match gets its missing side filled in — the tracked
    # counterpart has finally arrived, so the pair supersedes the stand-in.
    sig { returns(T.nilable(Transfer)) }
    def upgrade_one_sided
      side_missing = @txn.amount.to_f.negative? ? :from : :to
      side_present = side_missing == :from ? :to : :from

      candidates = Transfer.payments
        .where(counterparty_account_id: @txn.account_id)
        .where("#{side_missing}_transaction_id IS NULL")
        # Same sargable range form as find_counterparts: strict bounds keep
        # ABS(amount - b) < tol semantics exactly.
        .where("amount > ? AND amount < ?", @txn.amount.abs - TOLERANCE, @txn.amount.abs + TOLERANCE)

      transfer = candidates.detect do |t|
        other = t.public_send(:"#{side_present}_transaction")
        other.is_a?(CashTransaction) &&
          other.account_id != @txn.account_id &&
          (other.transaction_date - @txn.transaction_date).abs <= DAYS
      end
      return nil unless transfer

      # Two concurrent PaymentMatchJobs (one per leg of the same payment) can
      # both select this transfer; the row lock serializes them and the
      # re-check makes the loser walk away instead of overwriting the winner.
      claimed = transfer.with_lock do
        if transfer.public_send(:"#{side_missing}_transaction_id").nil?
          transfer.update!(
            counterparty_account_id: nil,
            "#{side_missing}_transaction_id":   @txn.id,
            "#{side_missing}_transaction_type": "CashTransaction",
            # Both legs are tracked now, so the pair default applies (loan
            # payments stay countable; card payments stop being a proxy).
            include_in_spend: transfer.kind == Transfer::Kind::LoanPayment ? transfer.include_in_spend : false
          )
          true
        else
          false
        end
      end
      return nil unless claimed

      transfer.sync_transfer_ids if transfer.confirmed?
      # sync_transfer_ids writes via update_all, which skips the after_commit
      # bump — rotate the cached-endpoint version explicitly.
      Households::DataVersion.bump_coalesced!(@txn.household_id)
      transfer
    end

    # S5 — cadence for untracked counterparties. A confirmed one-sided payment
    # already links this account to a counterparty for the same stable
    # descriptor (reference numbers stripped), so this occurrence is the same
    # payment: link it the same way. Restricted to payment-shaped legs so an
    # ordinary debit can never inherit a link, and to payment kinds so the
    # structural guardrail against payments-to-people still holds.
    sig { returns(T.nilable(Transfer)) }
    def replay_one_sided
      return nil unless PaymentSignals.payment_shaped?(@txn)

      key = PaymentSignals.normalize_description(@txn.description)
      return nil if key.blank?

      side = @txn.amount.to_f.negative? ? "from" : "to"
      precedent = Transfer.confirmed.payments
        .where.not(counterparty_account_id: nil)
        .where("transfers.#{side}_transaction_type = 'CashTransaction'")
        .joins("JOIN cash_transactions legs ON legs.id = transfers.#{side}_transaction_id")
        .where("legs.account_id = ?", @txn.account_id)
        .select("transfers.*, legs.description AS leg_description")
        .order("transfers.confirmed_at DESC")
        .limit(50)
        .detect { |t| PaymentSignals.normalize_description(t.read_attribute(:leg_description)).casecmp?(key) }
      return nil unless precedent

      transfer = Transfer.create!(
        household_id:              @txn.household_id,
        amount:                    @txn.amount.abs,
        kind:                      precedent.kind,
        include_in_spend:          precedent.include_in_spend,
        counterparty_account_id:   precedent.counterparty_account_id,
        "#{side}_transaction_id":   @txn.id,
        "#{side}_transaction_type": "CashTransaction"
      )
      transfer.confirm!(source: Transfer::ConfirmationSource::Auto)
      Workflows::Events.publish("transfer.auto_confirmed", subject: transfer,
                                payload: { "kind" => transfer.kind.serialize, "amount" => transfer.amount.to_s })
      transfer
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    sig { returns(T::Array[CashTransaction]) }
    def find_counterparts
      scope = CashTransaction
        .where(household_id: @txn.household_id)
        .where.not(id: @txn.id)
        .where.not(account_id: @txn.account_id)
        .where(transfer_id: nil)
        # Sargable range form of ABS(amount + a) < tol. Strict comparisons
        # (not BETWEEN, which is inclusive) keep the boundary semantics of
        # the original strict inequality.
        .where("amount > ? AND amount < ?", -@txn.amount - TOLERANCE, -@txn.amount + TOLERANCE)
        .where(transaction_date: (@txn.transaction_date - DAYS)..(@txn.transaction_date + DAYS))

      # Enforce the structural roles: the inflow leg must sit in a credit-card
      # account (unless this is a loan-marked pairing, where the inflow lands
      # on the liability account instead).
      if card_inflow?(@txn)
        scope = scope.source_bank.where("amount < 0")
      else
        scope = scope.where("amount > 0")
        unless PaymentSignals.loan_marked?([ @txn ])
          scope = scope.joins(:account).where(accounts: { account_type: KindClassifier::CREDIT_CARD_TYPE })
        end
      end

      scope.limit(2).to_a
    end

    sig { params(txn: CashTransaction).returns(T::Boolean) }
    def card_inflow?(txn)
      # T.must: Sorbet infers `bool && bool` as T.nilable(T::Boolean), which
      # doesn't satisfy the sig. Both operands type as plain booleans alone.
      T.must(txn.amount.to_f.positive? && txn.account&.account_type == KindClassifier::CREDIT_CARD_TYPE)
    end

    sig { params(txn: CashTransaction).returns(T::Boolean) }
    def bank_outflow?(txn)
      T.must(txn.amount.to_f.negative? && txn.source_bank?)
    end
  end
end
