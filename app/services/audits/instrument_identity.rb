# typed: strict

module Audits
  # Catches the failure mode that let ~1,300 duplicate securities accumulate in
  # July 2026: a no-ticker/no-cusip security created without a registered
  # instrument_identifier can never be re-matched by Instruments::Resolver on
  # the next sync, so a new duplicate gets minted every cycle instead.
  class InstrumentIdentity
    extend T::Sig

    sig { void }
    def call
      security_ids = InvestmentTransaction.where.not(security_id: nil).distinct.pluck(:security_id) +
                     PositionSnapshot.distinct.pluck(:security_id)
      return if security_ids.empty?

      orphans = Security.where(id: security_ids, ticker: nil, cusip: nil)
                         .where.not(name: [ nil, "" ])
                         .left_joins(:instrument_identifiers)
                         .where(instrument_identifiers: { id: nil })
                         .where("securities.created_at > ?", 1.day.ago)

      count = orphans.count
      if count > 0
        Issue.raise_once!(
          key:      "security_missing_identifier",
          title:    "#{count} new securities created without an external identifier",
          body:     "These securities have no ticker, CUSIP, or registered instrument_identifier. " \
                    "Instruments::Resolver won't be able to re-match them on the next sync, so they'll " \
                    "keep duplicating instead of updating in place. Check the ingestion path that " \
                    "created them (likely a sync that isn't passing a stable identifier through) — see " \
                    "Instruments::Resolver#register!.",
          severity: Severity::Error,
          source:   "system_audit"
        )
      else
        Issue.resolve!("security_missing_identifier")
      end
    end
  end
end
