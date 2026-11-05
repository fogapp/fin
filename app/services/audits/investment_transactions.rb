# typed: strict

module Audits
  # Watches the investment ledger for data that silently degrades portfolio
  # math: transactions with no resolved security, and referenced securities
  # with no price history.
  class InvestmentTransactions
    extend T::Sig

    # How far back a sold security still feeds valuations (charts, net-worth
    # history) — the scheduler backfills history for exactly this window.
    RELEVANT_HISTORY = T.let(MarketData::Scheduler::RECENTLY_SOLD_WINDOW, ActiveSupport::Duration)

    sig { void }
    def call
      # Transactions with no resolved security can't contribute to portfolio value
      missing_count = InvestmentTransaction.where(security_id: nil).count
      if missing_count > 0
        noun = missing_count == 1 ? "transaction" : "transactions"
        Issue.raise_once!(
          key:      "investment_missing_security",
          title:    "#{missing_count} investment #{noun} without a security",
          body:     "These transactions could not be matched to a known security and are excluded " \
                    "from portfolio value and performance calculations.",
          severity: Severity::Warning,
          source:   "system_audit"
        )
      else
        Issue.resolve!("investment_missing_security")
      end

      # Securities whose value this household's portfolio math needs — held
      # now, or traded within RELEVANT_HISTORY — with no price history from
      # any source (a provider, or the custodian for unlisted holdings). A
      # security sold long ago moves no chart; flagging every ticker ever
      # traded buried the few issues that matter.
      security_ids = InvestmentTransaction.where.not(security_id: nil)
                                          .distinct
                                          .pluck(:security_id)
      return if security_ids.empty?

      relevant_ids = relevant_security_ids(security_ids)
      unpriced_ids = relevant_ids - priced_security_ids(relevant_ids)

      Issue.raise_each!(Security.where(id: unpriced_ids).map do |sec|
        {
          key:      "security_no_prices:#{sec.id}",
          title:    "No price data — #{sec.display_name}",
          body:     "This security has investment transactions but no price history. " \
                    "Portfolio values and unrealized gain/loss will be inaccurate until prices are synced.",
          severity: Severity::Warning,
          source:   "system_audit"
        }
      end)

      # Auto-resolve everything else — priced now, or no longer relevant —
      # in one set-wise update with Issue.resolve!'s exact semantics
      # (active.where(key:).update_all) instead of one UPDATE per security.
      resolved_ids = security_ids - unpriced_ids
      return if resolved_ids.empty?

      Issue.active.where(key: resolved_ids.map { |id| "security_no_prices:#{id}" })
           .update_all(dismissed_at: Time.current)
    end

    private

    sig { params(security_ids: T::Array[String]).returns(T::Array[String]) }
    def relevant_security_ids(security_ids)
      held = Positions::CurrentPositions.new.relation.where("quantity > 0").pluck(:security_id)
      recent = InvestmentTransaction
        .joins(:transaction_type)
        .where(transaction_types: { category: Positions::Rebuild::POSITION_CATEGORIES })
        .where(security_id: security_ids, trade_date: (Date.current - RELEVANT_HISTORY)..)
        .distinct.pluck(:security_id)
      (security_ids & held) | recent
    end

    # Which of these have any price row at all. EXISTS stops at each
    # security's first index entry; a DISTINCT over the price tables read
    # every row they hold for these securities (millions) just to learn
    # whether there was one.
    sig { params(security_ids: T::Array[String]).returns(T::Array[String]) }
    def priced_security_ids(security_ids)
      return [] if security_ids.empty?

      has_candle = Candle.daily.where("candles.security_id = securities.id").arel.exists
      has_price  = MarketPrice.where("market_prices.security_id = securities.id").arel.exists
      Security.unscoped.where(id: security_ids).where(has_candle.or(has_price)).pluck(:id)
    end
  end
end
