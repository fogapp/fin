# typed: strict

module Positions
  # Converts ledger quantities into each instrument's current share units.
  # Adjusted closes are expressed in today's units (every close before a
  # split is divided by it), so a trade's quantity has to be multiplied by
  # the same splits before the two meet — 10 shares bought before a 4:1
  # split are 40 of today's shares. Only genuine share splits count
  # (CorporateAction#share_split?); spin-off price adjustments filed as
  # "splits" leave quantities alone.
  module SplitAdjustment
    extend T::Sig

    Splits = T.type_alias { T::Array[[ Date, BigDecimal ]] }

    # {security_id => [[ex_date, ratio], ...]} of share splits, oldest first.
    sig { params(security_ids: T::Array[String]).returns(T::Hash[String, Splits]) }
    def self.splits_by_security(security_ids)
      return {} if security_ids.empty?

      CorporateAction.splits.where(security_id: security_ids).order(:ex_date).to_a
        .select(&:share_split?)
        .group_by(&:security_id)
        .transform_values { |actions| actions.map { |a| [ a.ex_date, a.ratio.to_d ] } }
    end

    # Multiplier taking a quantity traded on `date` to current units: the
    # product of every split that went ex after that day. A trade on the ex
    # date itself is already in post-split units.
    sig { params(splits: T.nilable(Splits), date: Date).returns(BigDecimal) }
    def self.factor(splits, date)
      return BigDecimal("1") if splits.nil? || splits.empty?

      splits.reduce(BigDecimal("1")) { |acc, (ex_date, ratio)| ex_date > date ? acc * ratio : acc }
    end
  end
end
