# typed: strict

module Alchemy
  # Gas fees aren't tracked per transaction (user decision), so the ledger's
  # native-token quantity slowly overstates the observed on-chain balance on
  # active wallets. This sweep books one "Accumulated network fees" row
  # (code GAS, category "Transfer Out") per drifting (account, native token)
  # pair when the delta is gas-plausible, keeping reconciliation quiet
  # without raw AcceptBalance adjustments (whose ADJ-OUT is category "Sale"
  # and would leak into Sells stats).
  class GasDriftSweep
    extend T::Sig

    # A delta larger than this is not gas — leave it for reconciliation to
    # flag as real drift (missing transactions, unsupported network, etc).
    # 10%: the sweep only runs on native tokens after a COMPLETED backfill,
    # where ledger-over-observed has one physical explanation — years of gas
    # (zero-value contract calls burn gas without appearing in transfers).
    GAS_CAP_FRACTION = T.let(BigDecimal("0.10"), BigDecimal)   # 10% of balance
    GAS_CAP_FLOOR    = T.let(BigDecimal("0.05"), BigDecimal)   # or 0.05 tokens

    Result = Struct.new(:swept, :skipped, keyword_init: true)

    sig { returns(Result) }
    def call
      result = Result.new(swept: 0, skipped: 0)

      AlchemyWallet.active.includes(:account).find_each do |wallet|
        account = wallet.account
        next unless account
        # Without a completed backfill the ledger side is still partial —
        # any delta is history, not gas.
        next unless backfill_complete?(wallet)

        native_tickers(wallet).each do |ticker|
          sweep_pair(wallet, account, ticker, result)
        end
      end

      result
    end

    private

    sig { params(wallet: AlchemyWallet).returns(T::Boolean) }
    def backfill_complete?(wallet)
      states = wallet.alchemy_wallet_syncs.where(network: wallet.networks)
      states.any? && states.all?(&:backfill_completed?)
    end

    sig { params(wallet: AlchemyWallet).returns(T::Array[String]) }
    def native_tickers(wallet)
      wallet.networks.filter_map { |n| AlchemyWallet::NATIVE_TOKENS.dig(n, :ticker) }.uniq
    end

    sig { params(wallet: AlchemyWallet, account: Account, ticker: String, result: Result).void }
    def sweep_pair(wallet, account, ticker, result)
      security = Security.joins(:instrument_identifiers).find_by(
        instrument_identifiers: { scheme: InstrumentIdentifier::Scheme::CryptoSymbol.serialize,
                                  value: ticker }
      )
      return unless security

      position = Position.find_by(account_id: account.id, security_id: security.id)
      snapshot = PositionSnapshot.find_by(source_row_hash: "alchemy_wallet:#{wallet.id}:#{security.id}")
      return unless position && snapshot

      delta = position.quantity.to_d - snapshot.quantity.to_d
      return unless drifting?(delta, snapshot.quantity.to_d)

      cap = [ snapshot.quantity.to_d * GAS_CAP_FRACTION, GAS_CAP_FLOOR ].max
      if delta > cap
        result.skipped += 1
        return
      end

      hash = "alchemy_gas_sweep:#{account.id}:#{security.id}:#{Date.current}:#{delta.round(8)}"
      if InvestmentTransaction.exists?(source_row_hash: hash)
        result.skipped += 1
        return
      end

      price  = MarketData::PriceSeries.latest_quote(security)&.price.to_d
      amount = (delta * price).round(4)

      Workflows::Events.suppress do
        InvestmentTransaction.create!(
          household_id:     wallet.household_id,
          account:          account,
          security:         security,
          transaction_type: gas_type,
          trade_date:       Date.current,
          quantity:         delta,
          price_usd:        price.positive? ? price.round(6) : nil,
          amount_usd:       amount,
          cost_usd:         amount,
          local_currency:   "USD",
          description:      "Accumulated network fees",
          source_row_hash:  hash
        )
      end
      result.swept += 1
    rescue ActiveRecord::RecordNotUnique
      result.skipped += 1
    end

    # Mirrors Reconciliation::Engine#drift? — only correct what would
    # otherwise raise a drift Issue.
    sig { params(delta: BigDecimal, observed: BigDecimal).returns(T::Boolean) }
    def drifting?(delta, observed)
      return false if delta <= Reconciliation::Engine::QUANTITY_TOLERANCE

      base = [ observed.abs, BigDecimal("0.000001") ].max
      (delta / base) > Reconciliation::Engine::RELATIVE_TOLERANCE
    end

    sig { returns(TransactionType) }
    def gas_type
      TransactionType.find_or_create_by!(code: "GAS") do |t|
        t.code_description = "Network fees"
        t.category = TransactionType::Category::TRANSFER_OUT
      end
    end
  end
end
