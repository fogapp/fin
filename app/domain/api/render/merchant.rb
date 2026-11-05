# typed: strict

module Api
  module Render
    class Merchant < Api::Render::Base
      extend T::Sig

      include Concerns::MonthlySpend
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        counts = ::CashTransaction.group(:merchant_id).count

        ::Merchant.includes(:category).order(:name).map do |m|
          serialize(m).merge(transaction_count: counts[m.id] || 0)
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        merchant    = ::Merchant.includes(:category).find(params[:id])
        spend_scope = own_spend(merchant)

        serialize(merchant).merge(
          monthly_spend:   monthly_spend(spend_scope),
          monthly_counts:  monthly_counts(spend_scope),
          monthly_income:  monthly_income(merchant)
        )
      end

      sig { params(merchant: ::Merchant).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(merchant)
        {
          id:            merchant.id,
          name:          merchant.name,
          category_id:   merchant.category_id,
          category_name: merchant.category&.name,
          notes:         merchant.notes,
          excluded:      merchant.excluded
        }
      end

      private

      # The merchant's slice of CashTransaction.spend_like, the definition
      # every other spend figure uses. An excluded merchant drops out of
      # household totals, but its own page still charts what was spent there,
      # so the exclusion is lifted for this merchant only.
      sig { params(merchant: ::Merchant).returns(T.untyped) }
      def own_spend(merchant)
        scope = ::CashTransaction.where(merchant_id: merchant.id)
        return scope.spend_like unless merchant.excluded

        excluded = ::Current.excluded_merchant_ids ||= ::Merchant.excluded.pluck(:id)
        ::Current.set(excluded_merchant_ids: excluded - [ merchant.id ]) { scope.spend_like }
      end

      sig { params(scope: T.untyped).returns(T.untyped) }
      def monthly_counts(scope)
        scope
          .group_by_period(:month, :transaction_date)
          .count
          .transform_keys(&:to_s)
      end

      sig { params(merchant: T.untyped).returns(T.untyped) }
      def monthly_income(merchant)
        ::CashTransaction.source_bank
          .where(merchant_id: merchant.id)
          .where("amount > 0")
          .group_by_period(:month, :transaction_date)
          .sum(:amount)
          .transform_keys(&:to_s)
          .transform_values(&:to_f)
      end
    end
  end
end
