# typed: strict

module Api
  module Render
    # Month-in-review payload: cashflow vs the prior month, top categories and
    # merchants, the biggest transactions, net-worth movement, the budget
    # outcome, and what recurring charges cost. Everything is computed for a
    # CLOSED month (the ?month= param, defaulting to last month), so the
    # numbers never shift under the reader the way current-month stats do.
    class Review < Api::Render::Base
      extend T::Sig

      TOP_LIMIT = 5

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        month = month_param
        prev  = month.prev_month

        {
          month:         month.strftime("%Y-%m"),
          cashflow:      cashflow_summary(month, prev),
          top_categories: ranked(category_scope(month)),
          top_merchants:  ranked(merchant_scope(month)),
          largest_transactions: largest_transactions(month),
          net_worth:     net_worth_summary(month, prev),
          budget:        budget_summary(month),
          subscriptions: subscriptions_summary(month)
        }
      end

      private

      sig { returns(Date) }
      def month_param
        # Defaults to the just-closed month — a review is of a finished period.
        PeriodParams.parse_month(params[:month].presence, default: Date.current.prev_month)
      end

      sig { params(month: Date).returns(T::Range[Date]) }
      def month_range(month)
        month..month.end_of_month
      end

      sig { params(month: Date, prev: Date).returns(T::Hash[Symbol, T.untyped]) }
      def cashflow_summary(month, prev)
        {
          income:       income_total(month),
          spend:        spend_total(month),
          prev_income:  income_total(prev),
          prev_spend:   spend_total(prev)
        }.tap do |h|
          h[:net]          = (h[:income] - h[:spend]).round(2)
          h[:prev_net]     = (h[:prev_income] - h[:prev_spend]).round(2)
          h[:savings_rate] = h[:income] > 0 ? ((h[:net] / h[:income]) * 100).round(1) : nil
        end
      end

      sig { params(month: Date).returns(Float) }
      def income_total(month)
        ::CashTransaction.income_like.where(transaction_date: month_range(month)).sum(:amount).to_f.round(2).to_f
      end

      sig { params(month: Date).returns(Float) }
      def spend_total(month)
        (-::CashTransaction.spend_like.where(transaction_date: month_range(month)).sum(:amount).to_f).round(2).to_f
      end

      sig { params(month: Date).returns(T.untyped) }
      def category_scope(month)
        # Subcategories roll up into their parent, so a top-level category
        # never ranks against its own children.
        ::CashTransaction.spend_like.joins(:category)
          .joins("LEFT JOIN categories parent_categories ON parent_categories.id = categories.parent_id")
          .where(transaction_date: month_range(month))
          .group(
            Arel.sql("COALESCE(parent_categories.id, categories.id)"),
            Arel.sql("COALESCE(parent_categories.name, categories.name)")
          )
      end

      sig { params(month: Date).returns(T.untyped) }
      def merchant_scope(month)
        ::CashTransaction.spend_like.joins(:merchant)
          .where(transaction_date: month_range(month))
          .group("merchants.id", "merchants.name")
      end

      sig { params(scope: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def ranked(scope)
        scope.sum(:amount)
          .map { |(id, name), amount| { id: id, name: name, amount: (-amount.to_f).round(2) } }
          .select { |row| row[:amount].positive? }
          .sort_by { |row| -row[:amount] }
          .first(TOP_LIMIT)
      end

      sig { params(month: Date).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def largest_transactions(month)
        ::CashTransaction.spend_like
          .where(transaction_date: month_range(month))
          .includes(:merchant, :category)
          .order(Arel.sql("ABS(amount) DESC"))
          .limit(TOP_LIMIT)
          .map do |t|
            {
              id:               t.id,
              description:      t.merchant&.name || t.description,
              category_name:    t.category&.name,
              transaction_date: t.transaction_date.to_s,
              amount:           t.amount.to_f.abs.round(2)
            }
          end
      end

      # Net worth from the daily metric_points series: the last point at or
      # before each month end (points may be weekly-spaced when old).
      sig { params(month: Date, prev: Date).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def net_worth_summary(month, prev)
        ending   = net_worth_at(month.end_of_month)
        starting = net_worth_at(prev.end_of_month)
        return nil if ending.nil?

        {
          ending:   ending,
          starting: starting,
          change:   starting ? (ending - starting).round(2) : nil
        }
      end

      sig { params(date: Date).returns(T.nilable(Float)) }
      def net_worth_at(date)
        ::MetricPoint.for_key(:net_worth).where(date: ..date).order(date: :desc).pick(:value)&.to_f&.round(2)
      end

      sig { params(month: Date).returns(T::Hash[Symbol, T.untyped]) }
      def budget_summary(month)
        data = ::Budgets::Month.new(month: month).call
        { planned: data[:planned], actual: data[:actual], remaining: data[:remaining] }
      end

      sig { params(month: Date).returns(T::Hash[Symbol, T.untyped]) }
      def subscriptions_summary(month)
        paid = ::RecurringOccurrence.paid_like
          .where(charged_date: month_range(month))
        { paid_count: paid.count, paid_total: paid.sum(:amount).to_f.abs.round(2) }
      end
    end
  end
end
