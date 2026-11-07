# typed: strict

module Plaid
  # The holdings domain of a Plaid sync: upserts PositionSnapshots for every
  # reported holding, zero-stamps holdings Plaid stopped reporting, and
  # derives crypto-wallet account balances from holding values. Failures
  # land in result.sub_errors (never blocking the transactions cursor).
  class HoldingSync
    extend T::Sig

    sig { params(context: SyncContext).void }
    def initialize(context)
      @context = context
    end

    sig { params(result: ::PlaidSyncer::Result).void }
    def call(result)
      sub_errors_before = result.sub_errors.size
      response = @context.client.get_investment_holdings(@context.plaid_item.access_token)
      securities_map = @context.build_securities_map(response.securities, result)
      # Crypto wallets report institution_price/institution_value as 0; the only
      # USD price Plaid provides for them is close_price on the security.
      close_prices = T.let({}, T::Hash[String, BigDecimal])
      response.securities.each do |sec|
        close_price = sec.close_price&.to_d
        close_prices[sec.security_id] = close_price if close_price&.positive?
      end
      writer = ::Positions::SnapshotWriter.new(prefix: "plaid_holding", household_id: @context.plaid_item.household_id)
      wallet_totals = T.let(Hash.new(BigDecimal("0")), T::Hash[PlaidAccount, BigDecimal])
      failed_account_ids = T.let(Set.new, T::Set[String])

      response.holdings.each do |holding|
        pa = @context.plaid_account_for(holding.account_id)
        next unless pa&.linked?

        security = holding.security_id ? securities_map[holding.security_id] : nil
        next unless security

        quantity     = holding.quantity.to_d
        price        = holding.institution_price.to_d
        price        = close_prices.fetch(holding.security_id, BigDecimal("0")) if price.zero?
        market_value = holding.institution_value.to_d
        market_value = (quantity * price).round(2) if market_value.zero?
        cost_basis   = holding.cost_basis&.to_d&.round(2)

        writer.upsert!(
          [ pa.id, security.id ],
          account_id:               pa.account_id,
          security:                 security,
          quantity:                 quantity.round(6),
          price:                    price,
          market_value:             market_value,
          cost_basis:               cost_basis,
          unrealized_gain_loss:     cost_basis ? (market_value - cost_basis).round(2) : nil,
          unrealized_gain_loss_pct: cost_basis&.positive? ? (((market_value - cost_basis) / cost_basis) * 100).round(4) : nil
        )
        wallet_totals[pa] = T.must(wallet_totals[pa]) + market_value if pa.crypto_wallet?
        record_custodian_price(security, holding, price: price, quantity: quantity, market_value: market_value)
      rescue => e
        # Attribute the failure so it only protects its own account below.
        failed_account_id = pa&.account_id
        failed_account_ids << failed_account_id if failed_account_id
        result.sub_errors << { scope: "holding", security_id: holding.security_id, error: e.message }
        Rails.logger.warn("[PlaidSyncer] holding #{holding.security_id} failed: #{e.message}")
      end

      # A holding that failed to save is still held, so zeroing it would book a
      # phantom sale — but only for its own account. Blocking every account in
      # the item (as this used to) let one permanently-failing holding freeze
      # unrelated snapshots indefinitely, which is how 23 abandoned rows sat in
      # the portfolio for three weeks. A security that failed to *resolve* can
      # be held anywhere, so that still blocks the whole item.
      resolution_failed = result.sub_errors.drop(sub_errors_before)
                                .any? { |err| err[:scope] == "security_resolution" }
      unless resolution_failed
        writer.zero_stamp_missing!(under: @context.plaid_item.plaid_accounts.pluck(:id),
                                   skip_account_ids: failed_account_ids, clear_cost_basis: true)
      end

      # Crypto wallet accounts report balances.current = 0, so their account
      # balance is the market value of their holdings.
      wallet_totals.each do |pa, total|
        ::Positions::SnapshotWriter.set_holdings_balance!(T.must(pa.account), total, source: ::AccountBalanceSnapshot::Source::PlaidSync)
      end
    rescue ::Plaid::ApiError => e
      info = ErrorInfo.from(e)
      raise unless info.skippable_product_error?

      Rails.logger.warn("[PlaidSyncer] holdings sync skipped: #{info.code} #{info.message}")
    rescue => e
      result.sub_errors << { scope: "holdings", error: e.message }
      Rails.logger.warn("[PlaidSyncer] holdings sync failed for item #{@context.plaid_item.id}: #{e.message}")
    end

    private

    # Keeps a daily price history for instruments no market provider covers
    # (see MarketData::CustodianPrices). Dated by Plaid's price date when it
    # sends one. Never fails the holding: the snapshot is already saved, and
    # a failure here must not mark the account as failed (which would block
    # its zero-stamp).
    sig do
      params(security: ::Security, holding: T.untyped, price: BigDecimal, quantity: BigDecimal,
             market_value: BigDecimal).void
    end
    def record_custodian_price(security, holding, price:, quantity:, market_value:)
      date = holding.respond_to?(:institution_price_as_of) ? holding.institution_price_as_of : nil
      date = Date.parse(date.to_s) if date.present? && !date.is_a?(Date)
      ::MarketData::CustodianPrices.record!(security, date: date || Date.current, price: price,
                                                     quantity: quantity, market_value: market_value)
    rescue => e
      Rails.logger.warn("[PlaidSyncer] custodian price for #{security.id} not recorded: #{e.message}")
    end
  end
end
