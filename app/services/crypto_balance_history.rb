# typed: strict

# Daily USD total of crypto account balances: the latest snapshot per account
# per day, summed across accounts. Crypto accounts are identified by a
# non-USD balance currency (the Coinbase syncer's convention).
#
# Previously duplicated verbatim in the portfolio and crypto renderers.
class CryptoBalanceHistory
  extend T::Sig

  # { "YYYY-MM-DD" => Float } (unrounded; callers round for presentation)
  sig { returns(T::Hash[String, Float]) }
  def daily_totals
    account_ids = Account
      .where.not(balance_currency: [ nil, "USD" ])
      .where("balance > 0")
      .where.not(balance_usd: nil)
      .pluck(:id)
    return {} if account_ids.empty?

    # Local-day bucketing (see AccountBalanceSnapshot.local_date): evening
    # syncs must not book to the next day's total.
    day = AccountBalanceSnapshot.local_date
    latest_per_account_day = AccountBalanceSnapshot
      .where(account_id: account_ids)
      .where.not(balance_usd: nil)
      .select("DISTINCT ON (account_id, #{day.to_sql}) account_id, balance_usd, recorded_at")
      .order(:account_id, day, recorded_at: :desc)

    AccountBalanceSnapshot
      .from(latest_per_account_day, :account_balance_snapshots)
      .group(day)
      .sum(:balance_usd)
      .transform_keys(&:to_s)
      .transform_values(&:to_f)
      .sort.to_h
  end
end
