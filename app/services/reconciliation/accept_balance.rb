# typed: strict

module Reconciliation
  # Accepts the custodian's reported balance as truth for one holding by
  # writing a balancing adjustment into the ledger. This is the remediation
  # for drift caused by incomplete history (transfers in, positions that
  # predate the connected integration): the delta between what the custodian
  # reports and what the ledger accounts for becomes an explicit, visible
  # adjustment transaction — not silent data surgery.
  #
  # Cost basis uses the freshest known price when available (the standard
  # opening-balance convention); the adjustment is clearly labeled so it can
  # be corrected later if a better basis is known.
  module AcceptBalance
    extend T::Sig

    ADJUSTMENT_TYPES = T.let({
      buy:  { code: "ADJ-IN",  category: ::TransactionType::Category::PURCHASE, description: "Balance adjustment (in)" },
      sell: { code: "ADJ-OUT", category: ::TransactionType::Category::SALE,     description: "Balance adjustment (out)" }
    }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

    Result = Struct.new(:status, :delta, keyword_init: true)

    sig { params(account: Account, security: Security).returns(Result) }
    def self.call(account:, security:)
      observation = latest_observation(account, security)
      return Result.new(status: :no_observation, delta: 0) if observation.nil?

      # One transaction around read-rebuild-adjust: a failure between the
      # adjustment insert and the final rebuild must not leave the ledger with
      # the adjustment booked but the position row still stale.
      #
      # Suppression wraps the transaction (not just the create) because model
      # events publish from after_commit, which now fires at the OUTER commit
      # — synthetic bookkeeping must not fire user automations (a created-
      # transaction workflow reacting to hundreds of adjustments is the
      # Comcast incident with extra steps).
      Workflows::Events.suppress do
        ActiveRecord::Base.transaction do
          # Rebuild first so we adjust against the true ledger, not a stale row.
          position = Positions::Rebuild.call(account: account, security: security)
          ledger_qty = position&.quantity.to_d
          delta = observation.quantity.to_d - ledger_qty
          if delta.abs <= Engine::QUANTITY_TOLERANCE
            Issue.resolve!(Engine.finding_key(account, security))
            next Result.new(status: :in_sync, delta: 0)
          end

          spec = T.must(delta.positive? ? ADJUSTMENT_TYPES[:buy] : ADJUSTMENT_TYPES[:sell])
          transaction_type = TransactionType.find_or_create_by!(code: spec.fetch(:code)) do |tt|
            tt.category = spec.fetch(:category)
            tt.code_description = spec.fetch(:description)
          end
          price = MarketData::PriceSeries.latest_quote(security)&.price

          InvestmentTransaction.create!(
            account:          account,
            security:         security,
            transaction_type: transaction_type,
            trade_date:       observation.as_of_date,
            quantity:         delta.round(8),
            price_usd:        price,
            cost_usd:         price ? (delta.abs * price).round(4) : nil,
            description:      "Accepted custodian balance of #{observation.quantity.to_f} " \
                              "(ledger accounted for #{ledger_qty.to_f})",
            source_row_hash:  "reconcile_accept:#{account.id}:#{security.id}:#{observation.as_of_date}:#{delta.round(8)}"
          )

          Positions::Rebuild.call(account: account, security: security)
          Issue.resolve!(Engine.finding_key(account, security))
          Result.new(status: :adjusted, delta: delta)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # The identical adjustment landed concurrently — double-submit, no-op.
      Result.new(status: :already_accepted, delta: 0)
    rescue ActiveRecord::RecordInvalid => e
      # Structured dedup check (the old version matched on the error message
      # text): only the source_row_hash uniqueness validation means "the
      # identical adjustment already exists"; anything else is a real error.
      record = e.record
      raise unless record.is_a?(InvestmentTransaction) && record.errors.of_kind?(:source_row_hash, :taken)

      Result.new(status: :already_accepted, delta: 0)
    end

    # Newest custodian-reported quantity for the pair (imported or plaid —
    # never computed rows, which are ledger-derived themselves).
    sig { params(account: Account, security: Security).returns(T.nilable(PositionSnapshot)) }
    def self.latest_observation(account, security)
      PositionSnapshot.where(account_id: account.id, security_id: security.id)
                      .where.not("source_row_hash LIKE 'computed:%'")
                      .order(as_of_date: :desc, created_at: :desc)
                      .first
    end
    private_class_method :latest_observation
  end
end
