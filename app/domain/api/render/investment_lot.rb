# typed: strict

module Api
  module Render
    class InvestmentLot < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::InvestmentLot.where(security_id: params[:security_id]).includes(:account).map { |l| serialize(l) }
      end

      sig { params(lot: ::InvestmentLot).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(lot)
        {
          id:            lot.id,
          security_id:   lot.security_id,
          account_id:    lot.account_id,
          account_name:  lot.account&.name,
          acquired_date: lot.acquired_date&.to_s,
          quantity:      lot.quantity.to_f,
          cost_basis:    lot.cost_basis.to_f,
          unit_cost:     lot.unit_cost,
          notes:         lot.notes
        }
      end
    end
  end
end
