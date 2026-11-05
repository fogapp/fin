# typed: strict

module Api
  module Render
    class AccountHoldings < Api::Render::Base
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        account_id = params[:id]

        # includes, not just joins: the serializer below reads ticker/name/cusip
        # off each row's security, and a bare join preloads nothing — that was
        # one extra SELECT per holding on every account-detail load.
        snaps = ::Positions::CurrentPositions.new.relation
                                             .where(account_id: account_id)
                                             .includes(:security)
                                             .order(Arel.sql("market_value DESC NULLS LAST"))
        as_of = snaps.maximum(:as_of_date)
        labels = ::SecurityLabel.by_security(snaps.map(&:security_id).uniq)

        positions = snaps.map do |s|
          gl_pct = s.cost_basis.to_f > 0 ? (s.unrealized_gain_loss.to_f / s.cost_basis.to_f * 100).round(4) : 0.0
          {
            id:                s.id,
            security_id:       s.security_id,
            security_ticker:   s.security.ticker,
            security_name:     s.security.name,
            security_cusip:    s.security.cusip,
            security_label:    labels[s.security_id],
            quantity:          s.quantity.to_f,
            price:             s.price.to_f,
            market_value:      s.market_value.to_f,
            cost_basis:        (s.cost_basis_override || s.cost_basis).to_f,
            unrealized_gl:     s.unrealized_gain_loss.to_f,
            unrealized_gl_pct: gl_pct,
            asset_class:       s.asset_class,
            est_annual_income: s.est_annual_income.to_f,
            dividend_yield:    s.dividend_yield.to_f,
            as_of_date:        as_of
          }
        end

        { as_of_date: as_of, positions: positions }
      end
    end
  end
end
