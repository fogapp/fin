# typed: strict

module Equity
  # Pricing rules for equity comp. One resolved share price per company
  # (public quote first, latest FMV as fallback), and one value rule per
  # grant type: options are worth their intrinsic spread, full-value awards
  # (RSU/RSA) are worth price × quantity. USD everywhere for v1.
  module Valuation
    extend T::Sig

    sig { params(company: EquityCompany).returns(T.nilable(BigDecimal)) }
    def self.current_share_price(company)
      if company.public_company? && company.security_id.present?
        quote = company.security&.current_price
        return quote.to_d if quote.present?
      end
      company.latest_fmv&.price_per_share&.to_d
    end

    # nil (not zero) when no price is known — "we can't value this" must be
    # distinguishable from "this is worthless".
    sig { params(grant: EquityGrant, quantity: T.untyped, price: T.nilable(BigDecimal)).returns(T.nilable(BigDecimal)) }
    def self.grant_value(grant, quantity, price)
      return nil if price.nil? || quantity.nil?

      if grant.option?
        spread = price - grant.strike_price.to_d
        spread = BigDecimal("0") if spread.negative?
        spread * quantity.to_d
      else
        price * quantity.to_d
      end
    end
  end
end
