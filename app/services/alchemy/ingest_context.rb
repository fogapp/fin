# typed: strict

module Alchemy
  # Per-batch caches for transfer ingestion. Mapping issued 6–10 queries per
  # transfer (dedupe exists?, instrument resolution, price close, type row),
  # so a deep wallet backfill multiplied into tens of thousands of round
  # trips. One context per ingestor page memoizes the lookups that repeat
  # across the page — same tokens, same dates, the same two type rows — and
  # prefetches the already-ingested row hashes in a single query.
  class IngestContext
    extend T::Sig

    sig { params(wallet: AlchemyWallet).void }
    def initialize(wallet:)
      @wallet          = T.let(wallet, AlchemyWallet)
      @types           = T.let({}, T::Hash[Symbol, TransactionType])
      @securities      = T.let({}, T::Hash[[ String, String ], Security])
      @prices          = T.let({}, T::Hash[[ String, Date ], T.nilable(BigDecimal)])
      @fallback_prices = T.let({}, T::Hash[String, T.nilable(BigDecimal)])
      @existing_hashes = T.let(nil, T.nilable(T::Set[String]))
    end

    # One query for the page's candidate hashes instead of an exists? per
    # transfer. Uses the same (household-scoped) relation the per-row check
    # used.
    sig { params(hashes: T::Array[String]).void }
    def prefetch_existing!(hashes)
      @existing_hashes = InvestmentTransaction
        .where(source_row_hash: hashes)
        .pluck(:source_row_hash).to_set
    end

    sig { params(hash: String).returns(T::Boolean) }
    def existing_row?(hash)
      existing = @existing_hashes
      return existing.include?(hash) unless existing.nil?

      InvestmentTransaction.exists?(source_row_hash: hash)
    end

    sig { params(hash: String).void }
    def record_row!(hash)
      @existing_hashes&.add(hash)
    end

    sig { params(direction: Symbol).returns(TransactionType) }
    def transaction_type(direction)
      @types[direction] ||= if direction == :in
        TransactionType.find_or_create_by!(code: "XFER-IN") do |t|
          t.code_description = "Crypto transfer in"
          t.category = TransactionType::Category::TRANSFER_IN
        end
      else
        TransactionType.find_or_create_by!(code: "XFER-OUT") do |t|
          t.code_description = "Crypto transfer out"
          t.category = TransactionType::Category::TRANSFER_OUT
        end
      end
    end

    sig do
      params(instrument_class: String, ticker: String, name: String, security_type: String)
        .returns(Security)
    end
    def resolve_security(instrument_class:, ticker:, name:, security_type:)
      @securities[[ instrument_class, ticker ]] ||= Instruments::Resolver.resolve!(
        instrument_class: instrument_class,
        ticker:           ticker,
        name:             name,
        security_type:    security_type
      )
    end

    # Close on the trade date, falling back to the latest quote, then to the
    # last observed (non-computed) snapshot price — long-tail tokens often
    # exist in no candle/quote provider, but the balance sync stores
    # Alchemy's own price on every snapshot it writes. Better a
    # current-price basis than dropping the quantity from the ledger and
    # leaving permanent drift. Nil results are memoized too.
    sig { params(security: Security, trade_date: Date).returns(T.nilable(BigDecimal)) }
    def price_for(security, trade_date)
      key = [ security.id, trade_date ]
      return @prices[key] if @prices.key?(key)

      @prices[key] = MarketData::PriceSeries.close_on(security, trade_date) || fallback_price(security)
    end

    private

    sig { params(security: Security).returns(T.nilable(BigDecimal)) }
    def fallback_price(security)
      return @fallback_prices[security.id] if @fallback_prices.key?(security.id)

      @fallback_prices[security.id] =
        MarketData::PriceSeries.latest_quote(security)&.price || observed_snapshot_price(security)
    end

    sig { params(security: Security).returns(T.nilable(BigDecimal)) }
    def observed_snapshot_price(security)
      price = PositionSnapshot
        .where(household_id: @wallet.household_id, security_id: security.id)
        .where.not(price: nil)
        .where("source_row_hash NOT LIKE 'computed:%'")
        .order(as_of_date: :desc).limit(1).pick(:price)
      price&.positive? ? price.to_d : nil
    end
  end
end
