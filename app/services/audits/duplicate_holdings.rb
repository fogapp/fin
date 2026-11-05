# typed: strict

module Audits
  # The other half of the identity problem: Audits::InstrumentIdentity only
  # sees securities minted in the last day, so it never noticed that the
  # July 2026 resolver cutover left 23 identifier-less rows behind — each one
  # a second copy of a holding the account already had. CurrentPositions no
  # longer counts them (Positions::CurrentPositions::STALE_AFTER_DAYS), but a
  # holding split across two security rows still splits its lots, its
  # transactions and its cost basis, so it needs merging rather than hiding.
  class DuplicateHoldings
    extend T::Sig

    sig { void }
    def call
      plans = Instruments::PlaidDuplicates.new.plans
      if plans.any?
        names = plans.map { |plan| plan.keep.display_name }.uniq.sort
        Issue.raise_once!(
          key:      "duplicate_plaid_securities",
          title:    "#{plans.size} holding#{plans.size == 1 ? '' : 's'} split across two security rows",
          body:     "Plaid abandoned one security row for another and kept syncing into the new one, " \
                    "so each of these holdings exists twice: #{names.take(10).join(', ')}" \
                    "#{names.size > 10 ? " (+#{names.size - 10} more)" : ''}. " \
                    "Review with `bin/rails instruments:plaid_duplicates`, then merge with APPLY=1.",
          severity: Severity::Error,
          source:   "system_audit"
        )
      else
        Issue.resolve!("duplicate_plaid_securities")
      end
    end
  end
end
