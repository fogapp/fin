# typed: true

class InvestmentLot < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  belongs_to :security
  belongs_to :account, optional: true

  validates :quantity, :cost_basis, presence: true, numericality: true

  # {security_id => {quantity:, cost_basis:}} for lot-coverage checks.
  sig { params(security_ids: T::Array[T.untyped]).returns(T::Hash[T.untyped, T::Hash[Symbol, Float]]) }
  def self.totals_by_security(security_ids)
    where(security_id: security_ids)
      .group(:security_id)
      .pluck(:security_id, Arel.sql("SUM(quantity)"), Arel.sql("SUM(cost_basis)"))
      .each_with_object({}) do |(sid, qty, cost), h|
        h[sid] = { quantity: qty.to_f, cost_basis: cost.to_f }
      end
  end

  sig { returns(T.nilable(Float)) }
  def unit_cost
    return nil if quantity.nil? || quantity.zero?

    (cost_basis / quantity).to_f.round(4).to_f
  end
end
