# typed: strict

class CoinbaseSyncer
  extend T::Sig

  SYNCABLE_TYPES = %w[buy sell advanced_trade_fill].freeze

  Result = Struct.new(:added, :skipped, :errors, keyword_init: true)

  sig { void }
  def initialize
    @client  = T.let(CoinbaseClient.new, CoinbaseClient)
    @buy_tt  = T.let(TransactionType.find_by!(code: "BUY"), TransactionType)
    @sell_tt = T.let(TransactionType.find_by!(code: "SELL"), TransactionType)
    @broker  = T.let(Broker.find_or_create_by!(name: "Coinbase"), Broker)
  end

  sig { returns(CoinbaseSyncer::Result) }
  def call
    result = Result.new(added: 0, skipped: 0, errors: [])

    @client.accounts.each do |acct|
      sync_account(acct, result)
    rescue => e
      result.errors << { account: acct["name"], error: e.message }
    end

    result
  end

  private

  sig { params(acct: T.untyped, result: T.untyped).void }
  def sync_account(acct, result)
    account = Account.find_or_create_by!(broker: @broker, account_number: acct["id"]) do |a|
      a.name         = acct["name"]
      a.account_type = "crypto"
    end

    # BigDecimal: crypto balances carry more significant digits than a
    # Float holds. accounts.balance is stored at scale 2, so compare at that
    # scale — otherwise an unchanged fractional balance never equals its
    # stored value and re-records a snapshot every sync.
    raw_balance  = acct.dig("balance", "amount").to_d
    currency     = acct.dig("balance", "currency").presence || "USD"
    native_bal   = acct.dig("native_balance", "amount").to_d

    if raw_balance.round(2) != account.balance.to_d || currency != account.balance_currency
      balance_usd = currency == "USD" ? raw_balance : (native_bal > 0 ? native_bal : nil)
      account.update_columns(
        balance:          raw_balance,
        balance_currency: currency,
        balance_usd:      balance_usd
      )
      AccountBalanceSnapshot.record(account,
        balance:          raw_balance,
        balance_currency: currency,
        balance_usd:      balance_usd,
        source:           AccountBalanceSnapshot::Source::CoinbaseSync
      )
    end

    register_currency(currency) if raw_balance > 0 && currency != "USD"

    each_transaction(acct["id"]) do |txn|
      next unless SYNCABLE_TYPES.include?(txn["type"])
      next unless txn["status"] == "completed"
      sync_transaction(txn, account, acct.dig("balance", "currency"), result)
    rescue => e
      result.errors << { transaction: txn["id"], error: e.message }
    end
  rescue => e
    result.errors << { account: acct["name"], error: e.message }
  end

  sig { params(txn: T.untyped, account: T.untyped, ticker: T.untyped, result: T.untyped).void }
  def sync_transaction(txn, account, ticker, result)
    return if InvestmentTransaction.exists?(source_row_hash: txn["id"])

    tt, quantity, price_usd, amount_usd, commission = extract_fields(txn)
    return unless tt && quantity.positive?

    security = Instruments::Resolver.resolve!(
      instrument_class: "crypto", ticker: ticker, name: ticker,
      identifiers: { coinbase_code: ticker.to_s.upcase }
    )

    InvestmentTransaction.create!(
      account:          account,
      security:         security,
      transaction_type: tt,
      # Local trade date: Coinbase timestamps are UTC ISO8601; Date.parse
      # ignored the time entirely, so an evening PT trade booked to the UTC
      # (next) day.
      trade_date:       Time.zone.parse(txn["created_at"]).to_date,
      quantity:         quantity,
      price_usd:        price_usd,
      amount_usd:       amount_usd,
      commissions_usd:  commission,
      description:      txn["type"].humanize,
      source_row_hash:  txn["id"]
    )
    result.added += 1
  rescue ActiveRecord::RecordNotUnique
    result.skipped += 1
  end

  sig { params(txn: T.untyped).returns(T::Array[T.untyped]) }
  def extract_fields(txn)
    quantity   = txn.dig("amount", "amount").to_d.abs
    amount_usd = txn.dig("native_amount", "amount").to_d.abs
    price_usd  = quantity > 0 ? (amount_usd / quantity).round(6) : 0

    case txn["type"]
    when "advanced_trade_fill"
      fill = txn["advanced_trade_fill"]
      tt   = fill["order_side"] == "buy" ? @buy_tt : @sell_tt
      commission = fill["commission"].to_d
    when "buy"
      tt         = @buy_tt
      commission = txn.dig("buy", "fee", "amount").to_d
    when "sell"
      tt         = @sell_tt
      commission = txn.dig("sell", "fee", "amount").to_d
    else
      return [ nil ]
    end

    [ tt, quantity, price_usd, amount_usd, commission ]
  end

  # Make sure the currency has a crypto instrument (so it can be priced and
  # hold positions). Deliberately does NOT create a SecurityWatch: the
  # watchlist is an explicit user choice, and auto-watching every Coinbase
  # balance meant unwatched coins reappeared on the next sync.
  sig { params(ticker: T.untyped).void }
  def register_currency(ticker)
    Instruments::Resolver.resolve!(
      instrument_class: "crypto", ticker: ticker, name: ticker.to_s.upcase,
      identifiers: { coinbase_code: ticker.to_s.upcase }
    )
  end

  sig { params(account_id: T.untyped, block: T.untyped).returns(NilClass) }
  def each_transaction(account_id, &block)
    starting_after = T.let(nil, T.nilable(String))
    loop do
      resp = @client.account_transactions(account_id, limit: 100, starting_after: starting_after)
      data = resp["data"] || []
      data.each(&block)

      next_uri = resp.dig("pagination", "next_uri")
      break if next_uri.nil? || data.empty?

      qs             = URI.decode_www_form(URI.parse(next_uri).query.to_s).to_h
      starting_after = qs["starting_after"]
      break unless starting_after
    end
  end
end
