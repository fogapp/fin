# typed: true

module Api
  module V1
    class InvestmentTransactionsController < BaseController
      include Api::Render::Concerns::SerializesInvestmentTransaction

      INDEX_DEFAULT_LIMIT = 200
      # `limit=all` is an explicit opt-in for the Investments › Transactions
      # page, which filters/sorts/pages the full ledger client-side (a few
      # thousand rows). It still gets a ceiling so no request can serialize
      # an unbounded table; the numeric-limit ceiling is the shared
      # MAX_TRANSACTION_LIMIT.
      ALL_LIMIT = 10_000

      def index
        scope = ::InvestmentTransaction.all
        scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
        scope = scope.where(security_id: params[:security_id]) if params[:security_id].present?

        limit, offset =
          if params[:limit] == "all"
            [ ALL_LIMIT, 0 ]
          else
            window_params(default: INDEX_DEFAULT_LIMIT, max: MAX_TRANSACTION_LIMIT)
          end
        render json: all_for(scope, limit: limit, offset: offset)
      end

      def create
        type     = TransactionType.find_by!(category: params.require(:transaction_type))
        account  = Account.find(params.require(:account_id))
        security = params[:security_id].present? ? Security.find(params[:security_id]) : nil

        trade_date  = Date.parse(params.require(:trade_date))
        quantity    = params[:quantity].presence&.to_d
        price_usd   = params[:price_usd].presence&.to_d
        amount_usd  = params[:amount_usd].presence&.to_d
        description = params[:description].presence

        cost_usd   = quantity && price_usd ? (quantity * price_usd).abs : nil
        income_usd = InvestmentTransaction::INCOME_CATEGORIES.include?(type.category) ? amount_usd : nil

        txn = InvestmentTransaction.create!(
          account:          account,
          security:         security,
          transaction_type: type,
          trade_date:       trade_date,
          quantity:         quantity,
          price_usd:        price_usd,
          price_local:      price_usd,
          amount_usd:       amount_usd,
          amount_local:     amount_usd,
          cost_usd:         cost_usd,
          cost_local:       cost_usd,
          income_usd:       income_usd,
          income_local:     income_usd,
          description:      description,
          local_currency:   "USD",
          source_row_hash:  Digest::SHA256.hexdigest("manual:#{SecureRandom.hex(16)}")
        )

        RecalculatePositionService.new(transaction: txn).call

        render json: serialize_transaction(txn), status: :created
      end

      def reprocess
        txn  = InvestmentTransaction.includes(:transaction_type, :account, :security).find(params[:id])
        snap = RecalculatePositionService.new(transaction: txn).call
        if snap
          render json: { status: "updated", as_of_date: snap.as_of_date, market_value: snap.market_value.to_f }
        else
          render json: { status: "skipped", reason: "not a purchase or sale" }
        end
      end
    end
  end
end
