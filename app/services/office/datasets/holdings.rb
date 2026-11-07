# typed: strict

module Office
  module Datasets
    # Current positions, one row per account × security — the grain the
    # holdings tables show. Optionally narrowed to one account, which is how
    # the account detail page exports just what it displays.
    class Holdings
      extend T::Sig

      HEADER = T.let(
        [
          "Account", "Ticker", "Name", "CUSIP", "Asset class", "Quantity", "Price",
          "Market value", "Cost basis", "Unrealized G/L", "Unrealized G/L %",
          "Est. annual income", "Dividend yield %", "As of"
        ].freeze,
        T::Array[String]
      )

      sig { params(params: T::Hash[Symbol, T.untyped]).void }
      def initialize(params)
        @params = params
      end

      sig { returns(Grid) }
      def grid
        scope = ::Positions::CurrentPositions.new.relation.includes(:security, :account)
        scope = scope.where(account_id: @params[:account_id]) if @params[:account_id].present?
        snaps = scope.order(Arel.sql("market_value DESC NULLS LAST")).to_a
        as_of = snaps.filter_map(&:as_of_date).max

        rows = [ HEADER ] + snaps.map { |s| row(s, as_of) }
        Grid.new(title: title, rows: rows, filters: @params)
      end

      private

      sig { params(s: ::PositionSnapshot, as_of: T.nilable(Date)).returns(T::Array[T.untyped]) }
      def row(s, as_of)
        # cost_basis_override wins where someone corrected an import, the
        # same precedence the holdings API uses.
        cost = (s.cost_basis_override || s.cost_basis).to_f
        gl   = s.unrealized_gain_loss.to_f
        [
          s.account&.name,
          s.security&.ticker,
          s.security&.name,
          s.security&.cusip,
          s.asset_class,
          s.quantity.to_f,
          s.price.to_f,
          s.market_value.to_f.round(2),
          cost.round(2),
          gl.round(2),
          cost > 0 ? (gl / cost * 100).round(2) : nil,
          s.est_annual_income.to_f.round(2),
          s.dividend_yield.to_f,
          s.as_of_date || as_of
        ]
      end

      sig { returns(String) }
      def title
        account = ::Account.find_by(id: @params[:account_id]) if @params[:account_id].present?
        account ? "Holdings — #{account.name}" : "Holdings"
      end
    end
  end
end
