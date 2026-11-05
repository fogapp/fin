# typed: strict

module Api
  module Render
    class Tag < Api::Render::Base
      extend T::Sig

      include Concerns::MonthlySpend
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        counts = ::CashTransaction.joins(:cash_transaction_tags).group("cash_transaction_tags.tag_id").count
        # CashTransaction.spend_like everywhere: the same definition the
        # cashflow page uses, so a tag's total matches its drill-down there.
        spend  = ::CashTransaction.spend_like
                                  .joins(:cash_transaction_tags)
                                  .group("cash_transaction_tags.tag_id")
                                  .sum(:amount)

        ::Tag.order(:name).map do |t|
          serialize(t).merge(
            transaction_count: counts[t.id] || 0,
            total_spend:       -spend[t.id].to_f
          )
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        tag    = ::Tag.find(params[:id])
        tagged = ::CashTransaction.joins(:cash_transaction_tags)
                                  .where(cash_transaction_tags: { tag_id: tag.id })
        spend  = tagged.spend_like

        serialize(tag).merge(
          total_count:   tagged.count,
          total_spend:   -spend.sum(:amount).to_f,
          total_returns: spend.returns.sum(:amount).to_f,
          by_category:   spend_by_category(spend),
          monthly_spend: monthly_spend(spend)
        )
      end

      sig { params(tag: ::Tag).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(tag)
        { id: tag.id, name: tag.name }
      end

      private

      sig { params(spend: T.untyped).returns(T.untyped) }
      def spend_by_category(spend)
        spend
            .joins("LEFT JOIN categories ON categories.id = cash_transactions.category_id")
            .group("COALESCE(categories.name, 'Uncategorized')")
            .sum(:amount)
            .transform_values { |v| -v.to_f }
            .sort_by { |_, v| -v }
            .to_h
      end
    end
  end
end
