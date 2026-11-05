# typed: strict

module Plaid
  # Shared state for one PlaidSyncer run, handed to every per-domain sync
  # service: the item, the (single) API client, the optional single-account
  # scope, the first-sync flag, plus the two lookups more than one domain
  # needs — the plaid_account map and Plaid-security resolution.
  class SyncContext
    extend T::Sig

    # Plaid security.type values use spaces, not underscores.
    PLAID_SECURITY_TYPE_MAP = T.let({
      "equity"          => "Equity",
      "etf"             => "ETF",
      "mutual fund"     => "Mutual Fund",
      "fixed income"    => "Fixed Income",
      "cash"            => "Cash",
      "cryptocurrency"  => "Crypto"
    }.freeze, T::Hash[String, String])

    sig { returns(::PlaidItem) }
    attr_reader :plaid_item

    sig { returns(T.untyped) }
    attr_reader :client

    sig { returns(T.nilable(::PlaidAccount)) }
    attr_reader :only_account

    # True when the item had no cursor at sync start (first sync after a
    # link or reconnect) — gates the content-based dedup adoption path.
    sig { returns(T::Boolean) }
    attr_reader :first_sync

    sig do
      params(plaid_item: ::PlaidItem, client: T.untyped, only_account: T.nilable(::PlaidAccount),
             first_sync: T::Boolean).void
    end
    def initialize(plaid_item:, client:, only_account:, first_sync:)
      @plaid_item   = T.let(plaid_item, ::PlaidItem)
      @client       = T.let(client, T.untyped)
      @only_account = T.let(only_account, T.nilable(::PlaidAccount))
      @first_sync   = T.let(first_sync, T::Boolean)
      @pa_by_plaid_id = T.let(nil, T.untyped)
    end

    # plaid_accounts are created when an item is linked, never mid-sync, so a
    # memoized map replaces the per-row find_by lookups.
    sig { params(plaid_account_id: T.untyped).returns(T.nilable(::PlaidAccount)) }
    def plaid_account_for(plaid_account_id)
      @pa_by_plaid_id ||= @plaid_item.plaid_accounts.index_by(&:plaid_account_id)
      @pa_by_plaid_id[plaid_account_id]
    end

    # Single-account syncs process only that account's rows.
    sig { params(plaid_account_id: T.untyped).returns(T::Boolean) }
    def skip_account?(plaid_account_id)
      !!(@only_account && plaid_account_id != T.must(@only_account).plaid_account_id)
    end

    sig { params(plaid_securities: T.untyped, result: ::PlaidSyncer::Result).returns(T::Hash[String, T.nilable(::Security)]) }
    def build_securities_map(plaid_securities, result)
      plaid_securities.each_with_object({}) do |sec, map|
        map[sec.security_id] = find_or_create_security_from_plaid(sec)
      rescue => e
        result.sub_errors << { scope: "security_resolution", security_id: sec.security_id, error: e.message }
        Rails.logger.warn("[PlaidSyncer] failed to resolve security #{sec.security_id}: #{e.message}")
        map[sec.security_id] = nil
      end
    end

    private

    sig { params(sec: T.untyped).returns(T.nilable(::Security)) }
    def find_or_create_security_from_plaid(sec)
      ticker = sec.ticker_symbol.presence
      cusip  = sec.cusip.presence
      return nil if ticker.blank? && cusip.blank? && sec.security_id.blank?

      ::Instruments::Resolver.resolve!(
        instrument_class: ::Instruments::Resolver.classify_plaid(sec.type.to_s),
        ticker:           ticker,
        cusip:            cusip,
        name:             sec.name,
        security_type:    PLAID_SECURITY_TYPE_MAP.fetch(sec.type.to_s, "Other"),
        identifiers:      { plaid_security_id: sec.security_id }
      )
    end
  end
end
