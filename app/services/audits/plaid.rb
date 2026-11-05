# typed: strict

module Audits
  # Watches Plaid connections for the current household: items in error
  # state, items whose daily sync has gone stale, and connected accounts
  # never linked to a Fin account (whose transactions silently don't
  # import).
  class Plaid
    extend T::Sig

    sig { void }
    def call
      PlaidItem.find_each do |item|
        audit_item(item)
      end

      PlaidAccount.find_each do |pa|
        audit_account(pa)
      end
    end

    private

    sig { params(item: PlaidItem).void }
    def audit_item(item)
      if item.status == "error"
        Issue.raise_once!(
          key:      "plaid_item_error:#{item.id}",
          title:    "Plaid connection error — #{item.institution_name}",
          body:     item.error_message,
          severity: Severity::Error,
          source:   "system_audit"
        )
      else
        Issue.resolve!("plaid_item_error:#{item.id}")
      end

      if item.last_synced_at.nil? || item.last_synced_at < 2.days.ago
        last = item.last_synced_at&.strftime("%b %-d, %Y at %l:%M %p") || "never"
        Issue.raise_once!(
          key:      "plaid_stale_sync:#{item.id}",
          title:    "Plaid sync overdue — #{item.institution_name}",
          body:     "Last successful sync: #{last}. The daily sync job may have failed or been skipped.",
          severity: Severity::Warning,
          source:   "system_audit"
        )
      else
        Issue.resolve!("plaid_stale_sync:#{item.id}")
      end
    end

    sig { params(pa: PlaidAccount).void }
    def audit_account(pa)
      if pa.account_id.nil?
        Issue.raise_once!(
          key:      "plaid_unlinked_account:#{pa.id}",
          title:    "Plaid account not linked — #{pa.display_name}",
          body:     "This account is connected via Plaid but hasn't been linked to a Fin account. " \
                    "Transactions from this account are not being imported.\n\n" \
                    "Go to Settings → Integrations → Plaid to link it.",
          severity: Severity::Warning,
          source:   "system_audit"
        )
      else
        Issue.resolve!("plaid_unlinked_account:#{pa.id}")
      end
    end
  end
end
