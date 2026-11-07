# typed: strict

module Plaid
  # The balance domain of a Plaid sync: refreshes per-plaid-account balance
  # columns and, for linked non-crypto accounts, the ledger account balance
  # plus a snapshot. Failures land in result.sub_errors (never blocking the
  # transactions cursor).
  class BalanceSync
    extend T::Sig

    sig { params(context: SyncContext).void }
    def initialize(context)
      @context = context
    end

    sig { params(result: ::PlaidSyncer::Result).void }
    def call(result)
      response = @context.client.get_accounts(@context.plaid_item.access_token)
      response.accounts.each do |acct|
        pa = @context.plaid_account_for(acct.account_id)
        next unless pa
        pa.update!(
          balance_current:    acct.balances.current,
          balance_available:  acct.balances.available,
          balance_limit:      acct.balances.limit,
          balance_currency:   acct.balances.iso_currency_code || acct.balances.unofficial_currency_code,
          balance_updated_at: Time.current
        )
        next unless pa.linked? && acct.balances.current.present?
        # Crypto wallets always report a $0 account-level balance; their real
        # balance is derived from holdings in Plaid::HoldingSync.
        next if pa.crypto_wallet?
        account = T.must(pa.account)
        currency = acct.balances.iso_currency_code || acct.balances.unofficial_currency_code || "USD"
        balance_usd = currency == "USD" ? acct.balances.current : nil
        account.update_columns(balance: acct.balances.current, balance_currency: currency, balance_usd: balance_usd)
        ::AccountBalanceSnapshot.record(account, balance: acct.balances.current, balance_currency: currency, balance_usd: balance_usd, source: ::AccountBalanceSnapshot::Source::PlaidSync)
      end
    rescue => e
      result.sub_errors << { scope: "balances", error: e.message }
      Rails.logger.warn("[PlaidSyncer] balance sync failed for item #{@context.plaid_item.id}: #{e.message}")
    end
  end
end
