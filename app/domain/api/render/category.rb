# typed: strict

module Api
  module Render
    class Category < Api::Render::Base
      extend T::Sig

      include Concerns::MonthlySpend
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        counts = ::CashTransaction.group(:category_id).count

        ::Category.includes(:subcategories).order(:name).map do |c|
          serialize(c).merge(transaction_count: counts[c.id] || 0)
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        category = ::Category.includes(:subcategories, :parent).find(params[:id])

        # Include transactions for this category and all its subcategories.
        # Spend uses the app-wide CashTransaction.spend_like definition so
        # these totals add up to the cashflow page's category breakdown
        # (they used to count only card charges, which dropped bank debits
        # and still counted excluded merchants).
        sub_ids      = category.subcategories.map(&:id)
        category_ids = [ category.id ] + sub_ids
        spend        = ::CashTransaction.spend_like.where(category_id: category_ids)
        own_spend    = ::CashTransaction.spend_like.where(category_id: category.id)
        counts       = ::CashTransaction.where(category_id: category_ids).group(:category_id).count

        # One grouped query each instead of two queries per subcategory.
        sub_spend = ::CashTransaction.spend_like
          .where(category_id: sub_ids)
          .group(:category_id)
          .sum(:amount)
          .transform_values { |v| -v.to_f }
        serialize(category).merge(
          parent:        category.parent ? { id: T.must(category.parent).id, name: T.must(category.parent).name } : nil,
          subcategories: category.subcategories.map { |s|
            { id: s.id, name: s.name,
              transaction_count: counts[s.id] || 0,
              total_spend:       sub_spend[s.id] || 0.0 }
          },
          total_count:   counts.values.sum,
          total_spend:   -spend.sum(:amount).to_f,
          total_returns: spend.returns.sum(:amount).to_f,
          by_merchant:   spend_by_merchant(spend),
          monthly_spend:         monthly_spend(own_spend),
          monthly_spend_rollup:  monthly_spend(spend)
        )
      end

      sig { params(category: ::Category).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(category)
        { id: category.id, name: category.name, parent_id: category.parent_id,
          budget_kind: category.budget_kind, charitable: category.charitable }
      end

      private

      sig { params(spend: T.untyped).returns(T.untyped) }
      def spend_by_merchant(spend)
        spend
            .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
            .group("COALESCE(merchants.name, 'Unknown')")
            .sum(:amount)
            .transform_values { |v| -v.to_f }
            .sort_by { |_, v| -v }
            .to_h
      end
    end
  end
end
