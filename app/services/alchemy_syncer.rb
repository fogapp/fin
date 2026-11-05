# typed: strict

# Syncs on-chain balances for the household's active AlchemyWallets.
#
# For each wallet: fetch native + ERC-20 balances across its networks via
# the Alchemy Portfolio API, resolve each token to a crypto Security,
# aggregate quantities per token across networks (ETH on mainnet + Base is
# one position), and write PositionSnapshots plus a holdings-derived
# account balance — the same shape PlaidSyncer produces for crypto wallets.
#
# Tokens without a USD price are skipped: legitimate assets are priced by
# Alchemy's feed, while airdrop/dust spam is not (the lesson from Plaid's
# wallet data). Skips are tallied and surfaced as an Activity warning.
class AlchemySyncer
  extend T::Sig

  Result = Struct.new(:wallets, :positions, :skipped, :errors, keyword_init: true)

  sig { void }
  def initialize
    @client = T.let(AlchemyClient.new, T.untyped)
  end

  sig { returns(Result) }
  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result  = Result.new(wallets: 0, positions: 0, skipped: {}, errors: [])

    AlchemyWallet.active.find_each do |wallet|
      sync_wallet(wallet, result)
      result.wallets += 1
    rescue => e
      result.errors << { wallet: wallet.display_name, error: e.message }
      # update_columns: a validation failure elsewhere on the record must
      # not silently drop the error breadcrumb (update is non-bang).
      wallet.update_columns(last_error: e.message.truncate(255))
    end

    if result.skipped.any?
      Activity.record(
        source: "alchemy_sync", event: "sync.tokens_skipped", severity: Severity::Warning,
        summary: "Alchemy sync skipped #{result.skipped.values.sum} unpriced token(s): " \
                 "#{result.skipped.map { |k, v| "#{k}×#{v}" }.join(', ')}",
        payload: { skipped_tokens: result.skipped }
      )
    end
    Activity.record(
      source: "alchemy_sync", event: "sync.completed",
      severity: result.errors.any? ? Severity::Warning : Severity::Info,
      summary: "Alchemy sync: #{result.wallets} wallet(s), #{result.positions} position(s)" \
               "#{result.errors.any? ? ", #{result.errors.size} errors" : ''}",
      payload: { wallets: result.wallets, positions: result.positions, errors: result.errors.size },
      duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    )
    result
  end

  private

  sig { params(wallet: AlchemyWallet, result: Result).void }
  def sync_wallet(wallet, result)
    tokens   = @client.tokens_by_address(wallet.address, networks: wallet.networks)
    holdings = aggregate(tokens, result)
    record_known_contracts(wallet, tokens)
    account  = wallet.ensure_account!
    writer   = Positions::SnapshotWriter.new(prefix: "alchemy_wallet", household_id: wallet.household_id)
    total    = T.let(BigDecimal("0"), BigDecimal)

    failed = T.let([], T::Array[String])

    holdings.each_value do |h|
      security     = resolve_security(h)
      quantity     = h[:quantity].to_d
      price        = h[:price].to_d
      market_value = (quantity * price).round(2)
      total       += market_value

      writer.upsert!(
        [ wallet.id, security.id ],
        account_id:   account.id,
        security:     security,
        quantity:     quantity.round(18),
        price:        price,
        market_value: market_value,
        cost_basis:   nil,
        unrealized_gain_loss: nil,
        unrealized_gain_loss_pct: nil
      )
      result.positions += 1
    rescue => e
      # Per holding, so one unresolvable token doesn't cost the wallet every
      # other position it holds. The rest of this method is skipped below,
      # because both remaining steps need a complete picture.
      failed << h[:ticker].to_s.presence.to_s
      result.errors << { wallet: wallet.display_name, token: failed.last, error: e.message }
      Rails.logger.warn("[AlchemySyncer] #{wallet.display_name} token #{failed.last}: #{e.message}")
    end

    if failed.any?
      # Deliberately NOT zero-stamping or writing a balance from a partial
      # sync. Both would treat "we failed to read this token" as "the wallet
      # no longer holds it": zero-stamping erases a live position, and `total`
      # is short by whatever failed. Leaving the previous values intact makes
      # the wallet look stale, which is true and recoverable; writing them
      # would make it look wrong, which isn't.
      wallet.update_columns(last_error: "#{failed.size} token(s) failed: #{failed.join(', ')}".truncate(255))
      return
    end

    # A token the wallet no longer holds is zero-stamped, not left at its
    # old quantity.
    writer.zero_stamp_missing!(under: [ wallet.id ])

    Positions::SnapshotWriter.set_holdings_balance!(account, total, source: AccountBalanceSnapshot::Source::AlchemySync)
    wallet.update!(last_synced_at: Time.current, last_error: nil)
  end

  # Remember which ERC-20 contracts Alchemy priced for this wallet, per
  # network. The transaction mapper only ingests token transfers from these
  # contracts — a symbol-squatting scam token ("USDC" that isn't USDC) would
  # otherwise resolve to the real security and slip past price-based filters.
  sig { params(wallet: AlchemyWallet, tokens: T::Array[T.untyped]).void }
  def record_known_contracts(wallet, tokens)
    merged = T.let(wallet.known_token_contracts.deep_dup, T::Hash[String, T.untyped])
    tokens.each do |token|
      next if token["error"].present? || token["tokenAddress"].blank?
      next if usd_price(token).nil?

      network  = token["network"].to_s
      contract = token["tokenAddress"].to_s.downcase
      list = Array(merged[network])
      merged[network] = (list + [ contract ]).uniq.sort unless list.include?(contract)
    end
    wallet.update_columns(known_token_contracts: merged) unless merged == wallet.known_token_contracts
  end

  # Collapse raw token entries into one holding per ticker, summing
  # quantities across networks. Unpriced or malformed entries are tallied
  # into result.skipped instead of imported.
  sig { params(tokens: T::Array[T.untyped], result: Result).returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
  def aggregate(tokens, result)
    holdings = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

    tokens.each do |token|
      next if token["error"].present?

      network  = token["network"].to_s
      metadata = token["tokenMetadata"] || {}
      native   = token["tokenAddress"].nil?
      ticker   = native ? AlchemyWallet::NATIVE_TOKENS.dig(network, :ticker) : metadata["symbol"].presence
      name     = native ? AlchemyWallet::NATIVE_TOKENS.dig(network, :name) : (metadata["name"].presence || ticker)
      decimals = native ? 18 : metadata["decimals"]

      quantity = AlchemyClient.to_quantity(token["tokenBalance"], decimals)
      next unless quantity.positive?

      price = usd_price(token)
      if ticker.blank? || decimals.nil? || price.nil?
        key = ticker.presence || token["tokenAddress"].to_s.first(10)
        result.skipped[key] = result.skipped.fetch(key, 0) + 1
        next
      end

      holding = holdings[ticker] ||= { ticker: ticker, name: name, quantity: BigDecimal(0), price: price }
      holding[:quantity] += quantity
    end

    holdings
  end

  sig { params(token: T.untyped).returns(T.nilable(BigDecimal)) }
  def usd_price(token)
    price = Array(token["tokenPrices"]).find { |p| p["currency"] == "usd" }
    value = price && price["value"].to_d
    value&.positive? ? value : nil
  end

  sig { params(holding: T::Hash[Symbol, T.untyped]).returns(Security) }
  def resolve_security(holding)
    Instruments::Resolver.resolve!(
      instrument_class: "crypto",
      ticker:           holding[:ticker],
      name:             holding[:name],
      security_type:    Security::CRYPTO_TYPE
    )
  end
end
