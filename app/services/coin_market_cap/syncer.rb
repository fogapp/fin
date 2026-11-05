# typed: strict

module CoinMarketCap
  class Syncer
    extend T::Sig

    Result = Struct.new(:updated, :skipped, :errors, keyword_init: true)

    sig { void }
    def initialize
      @client = T.let(Client.new, CoinMarketCap::Client)
    end

    sig { returns(CoinMarketCap::Syncer::Result) }
    def call
      result = Result.new(updated: 0, skipped: 0, errors: [])

      # Runs under Current.set(household:) — Account is default-scoped to the
      # household and the watchlist is the household's own.
      # Only crypto accounts: a EUR/CAD bank account's currency is not a
      # crypto symbol and used to poison the CMC quote batch.
      accounts         = Account.where(account_type: "crypto")
                                .where.not(balance: nil).where.not(balance_currency: [ nil, "USD" ])
      account_symbols  = accounts.pluck(:balance_currency).map(&:upcase).uniq
      cryptos          = Security.where(security_type: Security::CRYPTO_TYPE).where.not(ticker: [ nil, "" ])
      # Quote every crypto instrument the household watches *or* holds. Held
      # coins are no longer auto-watched, so membership in the watchlist can't
      # be the only thing keeping their prices fresh.
      priced_cryptos   = cryptos.watched_by(Current.household)
                                .or(cryptos.where("UPPER(securities.ticker) IN (?)", account_symbols.presence || [ "" ]))
      security_symbols = priced_cryptos.pluck(:ticker)
      symbols          = (account_symbols + security_symbols).map(&:upcase).uniq

      if symbols.empty?
        Rails.logger.info("[CoinMarketCap::Syncer] no crypto symbols to price")
        return result
      end

      quote_data = @client.quote_data(symbols)
      prices     = quote_data.transform_values { |d| d[:price] }
      Rails.logger.info("[CoinMarketCap::Syncer] fetched prices for #{quote_data.size}/#{symbols.size} symbols")

      update_slugs(quote_data)

      accounts.each do |account|
        price = prices[account.balance_currency.upcase]
        unless price
          Rails.logger.warn("[CoinMarketCap::Syncer] no price for #{account.balance_currency} (account=#{account.name})")
          result.skipped += 1
          next
        end

        balance_usd = (account.balance.to_d * price.to_d).round(2)
        account.update_columns(balance_usd: balance_usd)
        AccountBalanceSnapshot.record(account, source: AccountBalanceSnapshot::Source::Scheduled)
        result.updated += 1
      rescue => e
        result.errors << { account: account.name, error: e.message }
      end

      priced_cryptos.each do |security|
        price = prices[security.ticker.upcase]
        next unless price

        MarketData::Providers::CoinMarketCap.write_quote!(security, price)
      rescue => e
        result.errors << { security: security.ticker, error: e.message }
      end

      upsert_coinbase_positions(prices)

      result
    end

    private

    sig { params(quote_data: T.untyped).void }
    def update_slugs(quote_data)
      slugs_by_ticker = quote_data.filter_map { |ticker, d| [ ticker, d[:slug] ] if d[:slug].present? }.to_h
      return if slugs_by_ticker.empty?

      Security.where(security_type: Security::CRYPTO_TYPE, ticker: slugs_by_ticker.keys).each do |security|
        slug = slugs_by_ticker[security.ticker.upcase]
        security.update_column(:slug, slug) if slug && security.slug != slug
      end
    end

    sig { params(prices: T.untyped).void }
    def upsert_coinbase_positions(prices)
      broker = Broker.find_by(name: "Coinbase")
      return unless broker

      accounts = Account.where(broker: broker)
                        .where.not(balance: nil)
                        .where.not(balance_currency: [ nil, "USD" ])
                        .where("balance > 0")

      securities_by_ticker = Security.where(security_type: Security::CRYPTO_TYPE, ticker: accounts.pluck(:balance_currency).map(&:upcase).uniq)
                                     .index_by { |s| s.ticker.upcase }

      writer = Positions::SnapshotWriter.new(prefix: "computed:coinbase", household_id: Current.household!.id)

      accounts.each do |account|
        ticker   = account.balance_currency.upcase
        price    = prices[ticker]
        security = securities_by_ticker[ticker]
        next unless price && security

        # BigDecimal throughout: crypto balances carry more significant
        # digits than a Float holds.
        quantity = account.balance.to_d
        price    = price.to_d
        writer.upsert!(
          [ account.id ],
          account_id:   account.id,
          security:     security,
          quantity:     quantity,
          price:        price.round(6),
          market_value: (quantity * price).round(4),
          asset_class:  "Crypto"
        )
      rescue => e
        Rails.logger.error("[CoinMarketCap::Syncer] position upsert failed for #{account.name}: #{e.message}")
      end
    end
  end
end
