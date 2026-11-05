# typed: true

class CorporateAction < ApplicationRecord
  extend T::Sig

  KINDS = %w[split dividend].freeze

  belongs_to :security

  validates :kind, inclusion: { in: KINDS }
  validates :ex_date, presence: true
  validates :ratio, presence: true, if: -> { T.bind(self, CorporateAction); kind == "split" }
  validates :amount, presence: true, if: -> { T.bind(self, CorporateAction); kind == "dividend" }

  scope :splits, -> { where(kind: "split") }

  # A real share split changes a holder's share count by a simple fraction —
  # 2:1, 4:1, 10:1, 25:1, 3:2, 1:10. Providers also file spin-off and
  # special-distribution price adjustments as "splits" (HON 1.061 and
  # 0.9535, FTV 1.327, FDX 1.241): those rescale the adjusted price history
  # but leave the share count alone, so quantities must not follow them. A
  # ratio is a share split when it, or its inverse, is within
  # SPLIT_TOLERANCE (relative) of p/q with q <= 4 and p <= 100.
  SPLIT_MAX_DENOMINATOR = 4
  SPLIT_MAX_NUMERATOR   = 100
  SPLIT_TOLERANCE       = BigDecimal("0.0001")

  sig { params(ratio: T.untyped).returns(T::Boolean) }
  def self.share_split_ratio?(ratio)
    return false if ratio.nil?

    r = ratio.to_d
    return false unless r.positive?
    return false if (r - 1).abs <= SPLIT_TOLERANCE

    simple_fraction?(r) || simple_fraction?(BigDecimal("1") / r)
  end

  sig { params(value: BigDecimal).returns(T::Boolean) }
  def self.simple_fraction?(value)
    (1..SPLIT_MAX_DENOMINATOR).any? do |q|
      p = (value * q).round
      p.between?(1, SPLIT_MAX_NUMERATOR) && ((value - (BigDecimal(p) / q)).abs / value) <= SPLIT_TOLERANCE
    end
  end
  private_class_method :simple_fraction?

  sig { returns(T::Boolean) }
  def share_split?
    kind == "split" && self.class.share_split_ratio?(ratio)
  end
end
