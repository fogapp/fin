# typed: strict

module Plaid
  # The investment-transaction domain of a Plaid sync: pages the date-window
  # /investments/transactions API and ingests trades/income rows. Unmappable
  # type/subtype pairs are tallied in #skipped_types for the coordinator's
  # activity warning. Failures land in result.sub_errors (never blocking the
  # transactions cursor).
  class InvestmentTransactionSync
    extend T::Sig

    # Subtype takes priority — Plaid often sends income as fee/interest or fee/dividend.
    PLAID_SUBTYPE_MAP = T.let({
      "dividend"                => "DIV",
      "qualified dividend"      => "DIV",
      "non-qualified dividend"  => "DIV",
      "interest"                => "INT",
      "buy"                     => "BUY",
      "sell"                    => "SELL",
      "short-term capital gain" => "SELL",
      "long-term capital gain"  => "SELL"
    }.freeze, T::Hash[String, String])

    # Fallback when subtype doesn't match — only for unambiguous top-level types.
    PLAID_TYPE_MAP = T.let({
      "buy"  => "BUY",
      "sell" => "SELL",
      "fee"  => "FEE"
    }.freeze, T::Hash[String, String])

    TT_CATEGORIES = T.let({
      "BUY" => ::TransactionType::Category::PURCHASE, "SELL" => ::TransactionType::Category::SALE,
      "DIV" => ::TransactionType::Category::DIVIDEND, "INT" => ::TransactionType::Category::INTEREST,
      "FEE" => ::TransactionType::Category::FEES
    }.freeze, T::Hash[String, String])

    sig { returns(T::Hash[String, Integer]) }
    attr_reader :skipped_types

    # NOTE: the start window reads plaid_item.last_synced_at at construction
    # time — the coordinator must build this service BEFORE stamping a new
    # last_synced_at for the current run.
    sig { params(context: SyncContext).void }
    def initialize(context)
      @context       = T.let(context, SyncContext)
      @skipped_types = T.let(Hash.new(0), T::Hash[String, Integer])

      # Plaid investments is a date-window API and transactions post with a
      # 1-3 day lag; a window starting at last_synced_at loses them forever.
      # Re-query a trailing 30-day overlap (dedup makes it idempotent), and do
      # the full 2-year backfill whenever this item has no investment history
      # (covers first syncs that previously hit PRODUCT_NOT_READY).
      plaid_item = context.plaid_item
      has_history = ::InvestmentTransaction
        .where(account_id: plaid_item.plaid_accounts.select(:account_id))
        .exists?
      @start_date = T.let(
        if has_history && plaid_item.last_synced_at
          [ T.must(plaid_item.last_synced_at).to_date - 30, 2.years.ago.to_date ].max
        else
          2.years.ago.to_date
        end, Date
      )
    end

    sig { params(result: ::PlaidSyncer::Result).void }
    def call(result)
      end_date = Date.current
      offset     = 0

      loop do
        response = @context.client.get_investment_transactions(
          @context.plaid_item.access_token,
          start_date: @start_date,
          end_date:   end_date,
          offset:     offset
        )

        securities_map = @context.build_securities_map(response.securities, result)

        response.investment_transactions.each do |txn|
          next if @context.skip_account?(txn.account_id)
          process_investment_transaction(txn, securities_map)
        rescue => e
          result.sub_errors << { scope: "investment_transaction", transaction_id: txn.investment_transaction_id, error: e.message }
          Rails.logger.warn("[PlaidSyncer] investment txn #{txn.investment_transaction_id} failed: #{e.message}")
        end

        offset += response.investment_transactions.size
        break if offset >= response.total_investment_transactions
      end
    rescue ::Plaid::ApiError => e
      # Skip gracefully if the product isn't available, user hasn't consented, or we're rate-limited
      raise unless ErrorInfo.from(e).skippable_product_error?
    end

    private

    sig { params(txn: T.untyped, securities_map: T::Hash[String, T.nilable(::Security)]).void }
    def process_investment_transaction(txn, securities_map)
      plaid_account = @context.plaid_account_for(txn.account_id)
      return unless plaid_account&.linked?

      # Crypto wallets render every on-chain transfer as a zero-amount "fee"
      # row (quantity = token amount, amount/price/fees all 0), including
      # airdrop spam. No financial content — skip rather than import.
      return if txn.type.to_s == "fee" && txn.amount.to_f.zero? && txn.fees.to_f.zero?

      hash = txn.investment_transaction_id
      return if ::InvestmentTransaction.exists?(source_row_hash: hash)

      tt_code = PLAID_SUBTYPE_MAP[txn.subtype.to_s] || PLAID_TYPE_MAP[txn.type.to_s]
      unless tt_code
        # Tally instead of silently dropping — surfaced as an activity warning
        # at the end of the sync.
        key = "#{txn.type}/#{txn.subtype}"
        @skipped_types[key] = @skipped_types[key].to_i + 1
        return
      end

      tt = ::TransactionType.find_or_create_by!(code: tt_code) do |t|
        t.category = TT_CATEGORIES[tt_code]
        t.code_description = tt_code
      end

      security = txn.security_id ? securities_map[txn.security_id] : nil
      category = tt.category
      income   = %w[Dividend Interest].include?(category) ? txn.amount.to_f.abs : nil

      ::InvestmentTransaction.create!(
        account:          T.must(plaid_account.account),
        security:         security,
        transaction_type: tt,
        trade_date:       txn.date,
        quantity:         txn.quantity.to_f.abs,
        price_usd:        txn.price,
        amount_usd:       txn.amount.to_f.abs,
        income_usd:       income,
        commissions_usd:  txn.fees,
        description:      txn.name,
        source_row_hash:  hash
      )
    end
  end
end
