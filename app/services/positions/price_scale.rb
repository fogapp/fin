# typed: strict

module Positions
  # Dollars per (quantity × quoted price) for a position. Bonds (and
  # similar face-value instruments) are quoted per 100 of face value —
  # quantity is the face amount, so quantity * price overstates market value
  # 100x. The custodian's market value is the true dollar value, so the
  # quoting convention is backed out by comparing it to quantity * price,
  # snapping to the known 1% convention rather than trusting the raw ratio
  # (accrued interest / FX / rounding make it noisy around 1.0 for ordinary
  # per-share securities).
  #
  # A sold-out position's snapshot reads quantity 0 and can't show the
  # ratio; the convention remembered on the security (quoted_per_hundred?)
  # covers it, so its history isn't valued at 100x.
  module PriceScale
    extend T::Sig

    PER_HUNDRED = 0.01

    sig { params(snap: T.untyped).returns(Float) }
    def self.for(snap)
      ratio = from_ratio(quantity: snap.quantity, price: snap.price, market_value: snap.market_value)
      return ratio if ratio

      snap.security&.quoted_per_hundred? ? PER_HUNDRED : 1.0
    end

    # The scale a (quantity, price, market value) observation implies, or nil
    # when any of them is missing or zero.
    sig { params(quantity: T.untyped, price: T.untyped, market_value: T.untyped).returns(T.nilable(Float)) }
    def self.from_ratio(quantity:, price:, market_value:)
      qty, px, value = quantity.to_f, price.to_f, market_value.to_f
      return nil if qty.zero? || px.zero? || value.zero?

      (value / (qty * px)).between?(0.005, 0.05) ? PER_HUNDRED : 1.0
    end
  end
end
