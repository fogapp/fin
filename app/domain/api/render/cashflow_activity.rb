# typed: strict

module Api
  module Render
    class CashflowActivity < Api::Render::Base
      extend T::Sig

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        today    = Date.current
        from     = today - 29.days

        spend_scope  = ::CashTransaction.spend_like.where(transaction_date: from..)
        income_scope = ::CashTransaction.income_like.where(transaction_date: from..)

        daily_spend  = spend_scope.group(:transaction_date).sum(:amount)
          .transform_values { |v| (-v.to_f).round(2) }
        daily_income = income_scope.group(:transaction_date).sum(:amount)
          .transform_values { |v| v.to_f.round(2) }

        days = (from..today).map do |date|
          {
            date:   date.to_s,
            spend:  daily_spend[date]  || 0.0,
            income: daily_income[date] || 0.0
          }
        end

        total_spend  = days.sum { |d| d[:spend] }.round(2)
        total_income = days.sum { |d| d[:income] }.round(2)

        {
          days:         days,
          total_spend:  total_spend,
          total_income: total_income,
          net:          (total_income - total_spend).round(2)
        }
      end
    end
  end
end
