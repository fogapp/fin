# typed: strict

module Alchemy
  # Maps one normalized on-chain transfer into an InvestmentTransaction on
  # the wallet's account. Direction lives in the transaction type's category
  # ("Transfer In"/"Transfer Out" — position-affecting but excluded from
  # buy/sell stats); quantity is stored absolute per house convention.
  #
  # Both directions are priced at the market close on the transfer date
  # (amount_usd = cost_usd = qty × price), which keeps rows independent of
  # ingestion order and re-runnable. Wallet-to-wallet moves between two
  # household wallets get both legs linked with a confirmed Transfer.
  class TransferMapper
    extend T::Sig

    ALLOWED_CATEGORIES = T.let(%w[external internal erc20].freeze, T::Array[String])

    Result = Struct.new(:status, :transaction, keyword_init: true)
    # status: :created | :duplicate | :skipped_category | :skipped_zero |
    #         :skipped_self | :skipped_unrelated | :skipped_malformed |
    #         :skipped_unknown_token | :skipped_unpriced

    sig do
      params(
        wallet: AlchemyWallet, network: String, transfer: T::Hash[Symbol, T.untyped],
        context: T.nilable(IngestContext)
      ).returns(Result)
    end
    def self.call(wallet:, network:, transfer:, context: nil)
      new(wallet: wallet, network: network, transfer: transfer, context: context).call
    end

    # The canonical row-hash format — shared with IngestContext prefetching.
    sig { params(network: String, unique_id: String, direction: Symbol).returns(String) }
    def self.row_hash(network:, unique_id:, direction:)
      "alchemy_transfer:#{network}:#{unique_id}:#{direction}"
    end

    sig do
      params(
        wallet: AlchemyWallet, network: String, transfer: T::Hash[Symbol, T.untyped],
        context: T.nilable(IngestContext)
      ).void
    end
    def initialize(wallet:, network:, transfer:, context: nil)
      @wallet   = wallet
      @network  = network
      @transfer = transfer
      @context  = T.let(context || IngestContext.new(wallet: wallet), IngestContext)
    end

    sig { returns(Result) }
    def call
      return skip(:skipped_category) unless ALLOWED_CATEGORIES.include?(category)

      value = T.let(@transfer[:value], T.nilable(BigDecimal))
      return skip(:skipped_zero) unless value&.positive?

      from = @transfer[:from].to_s.downcase
      to   = @transfer[:to].to_s.downcase
      return skip(:skipped_self) if from == to

      direction = if to == @wallet.address then :in
      elsif from == @wallet.address then :out
      end
      return skip(:skipped_unrelated) if direction.nil?

      hash = source_row_hash(direction)
      return skip(:duplicate) if @context.existing_row?(hash)

      # Symbol-squatting spam would resolve to the real security and price
      # fine — only contracts the balance sync has seen priced get in.
      return skip(:skipped_unknown_token) if erc20? && !known_contract?

      trade_date = parse_trade_date
      return skip(:skipped_malformed) if trade_date.nil? || ticker.blank?

      security = resolve_security
      price    = price_for(security, trade_date)
      return skip(:skipped_unpriced) if price.nil?

      amount = (value * price).round(4)
      txn = InvestmentTransaction.create!(
        household_id:     @wallet.household_id,
        account:          @wallet.ensure_account!,
        security:         security,
        transaction_type: transaction_type(direction),
        trade_date:       trade_date,
        quantity:         value,
        price_usd:        price.round(6),
        amount_usd:       amount,
        cost_usd:         amount,
        local_currency:   "USD",
        description:      description(direction, from, to, value),
        source_row_hash:  hash
      )
      @context.record_row!(hash)
      link_self_transfer(txn, direction, direction == :in ? from : to, hash)
      Result.new(status: :created, transaction: txn)
    rescue ActiveRecord::RecordNotUnique
      Result.new(status: :duplicate)
    end

    private

    sig { params(status: Symbol).returns(Result) }
    def skip(status) = Result.new(status: status)

    sig { returns(String) }
    def category = @transfer[:category].to_s

    sig { returns(T::Boolean) }
    def erc20? = category == "erc20"

    sig { params(direction: Symbol).returns(String) }
    def source_row_hash(direction)
      self.class.row_hash(network: @network, unique_id: @transfer[:unique_id].to_s, direction: direction)
    end

    sig { returns(T::Boolean) }
    def known_contract?
      contract = @transfer[:contract_address].to_s.downcase
      Array(@wallet.known_token_contracts[@network]).include?(contract)
    end

    sig { returns(T.nilable(Date)) }
    def parse_trade_date
      # Local trade date from the UTC block timestamp (the CoinbaseSyncer
      # lesson: Date.parse on an ISO8601 books evening trades to the wrong day).
      raw = @transfer[:block_timestamp].presence
      raw && Time.zone.parse(raw.to_s)&.to_date
    rescue ArgumentError
      nil
    end

    sig { returns(T.nilable(String)) }
    def ticker
      if erc20?
        @transfer[:asset].presence
      else
        AlchemyWallet::NATIVE_TOKENS.dig(@network, :ticker)
      end
    end

    sig { returns(Security) }
    def resolve_security
      name = erc20? ? @transfer[:asset].presence : AlchemyWallet::NATIVE_TOKENS.dig(@network, :name)
      @context.resolve_security(
        instrument_class: "crypto",
        ticker:           T.must(ticker),
        name:             name || T.must(ticker),
        security_type:    Security::CRYPTO_TYPE
      )
    end

    sig { params(security: Security, trade_date: Date).returns(T.nilable(BigDecimal)) }
    def price_for(security, trade_date)
      @context.price_for(security, trade_date)
    end

    sig { params(direction: Symbol).returns(TransactionType) }
    def transaction_type(direction)
      @context.transaction_type(direction)
    end

    sig { params(direction: Symbol, from: String, to: String, value: BigDecimal).returns(String) }
    def description(direction, from, to, value)
      counterparty = direction == :in ? from : to
      verb         = direction == :in ? "Received" : "Sent"
      preposition  = direction == :in ? "from" : "to"
      qty          = value.round(8).to_s("F").sub(/\.?0+\z/, "")
      "#{verb} #{qty} #{ticker} #{preposition} #{short_address(counterparty)} · #{@network} · #{@transfer[:hash]}"
    end

    sig { params(address: String).returns(String) }
    def short_address(address)
      "#{address.first(6)}…#{address.last(4)}"
    end

    # When the counterparty is another household wallet, this transfer will
    # (or already did) produce a mirror leg keyed by the same uniqueId with
    # the direction flipped. Whichever leg maps second links the pair —
    # order-independent, so poll/backfill/webhook interleavings converge.
    sig { params(txn: InvestmentTransaction, direction: Symbol, counterparty_address: String, hash: String).void }
    def link_self_transfer(txn, direction, counterparty_address, hash)
      return if txn.amount_usd.to_d <= 0 # Transfer validates amount > 0

      # unscoped + explicit household: mapping runs in background jobs where
      # Current.household may be unset.
      other = AlchemyWallet.unscoped
        .where(household_id: @wallet.household_id, active: true)
        .find_by(address: counterparty_address)
      return unless other

      mirror_hash = direction == :in ? hash.sub(/:in\z/, ":out") : hash.sub(/:out\z/, ":in")
      mirror = InvestmentTransaction.unscoped
        .where(household_id: @wallet.household_id)
        .find_by(source_row_hash: mirror_hash)
      return unless mirror
      return if txn.transfer_id.present? || mirror.transfer_id.present?

      out_leg, in_leg = direction == :out ? [ txn, mirror ] : [ mirror, txn ]
      transfer = Transfer.create!(
        household_id:          @wallet.household_id,
        kind:                  Transfer::Kind::Transfer,
        amount:                txn.amount_usd.to_d.abs,
        from_transaction_type: "InvestmentTransaction",
        from_transaction_id:   out_leg.id,
        to_transaction_type:   "InvestmentTransaction",
        to_transaction_id:     in_leg.id
      )
      transfer.confirm!(source: Transfer::ConfirmationSource::Auto)
    end
  end
end
