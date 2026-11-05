# typed: strict

module Api
  module Render
    class NetWorth < Api::Render::Base
      extend T::Sig

      # An explicit from/to (any timeframe button) takes precedence over the
      # named range, which older clients still send.
      sig { params(range: NetWorthHistory::RangeKey).returns(T::Hash[Symbol, T.untyped]) }
      def index(range:)
        NetWorthHistory.new(range: range, from: date_param(:from), to: date_param(:to)).call
      end

      # A deliberately simple forward projection: compound the current net
      # worth at a flat annual growth rate while adding a flat monthly
      # contribution. The defaults are honest ones — the latest net-worth
      # metric point and the trailing-12-month average of income minus spend —
      # and both knobs are overridable, so the chart answers "roughly where
      # does this trajectory land?" without pretending to be a planning engine.
      DEFAULT_YEARS  = 10
      DEFAULT_GROWTH = 5.0
      CONTRIBUTION_LOOKBACK_MONTHS = 12

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def projection
        years   = (params[:years].presence || DEFAULT_YEARS).to_i.clamp(1, 40)
        growth  = (params[:growth].presence || DEFAULT_GROWTH).to_f.clamp(-20.0, 30.0)
        monthly = params[:monthly].present? ? params[:monthly].to_f : default_monthly_contribution

        starting = ::MetricPoint.for_key(:net_worth).order(date: :desc).pick(:value)&.to_f || 0.0
        rate = growth / 100.0 / 12.0

        value = starting
        date  = Date.current.beginning_of_month
        series = Array.new(years * 12) do
          value = value * (1 + rate) + monthly
          date  = date.next_month
          { month: date.strftime("%Y-%m"), value: value.round(2) }
        end

        {
          starting:              starting.round(2),
          monthly_contribution:  monthly.round(2),
          annual_growth_percent: growth,
          years:                 years,
          series:                series
        }
      end

      private

      # Trailing average monthly net savings over closed months only, so the
      # current partial month doesn't drag the default down.
      sig { returns(Float) }
      def default_monthly_contribution
        to   = Date.current.beginning_of_month - 1.day
        from = (to - (CONTRIBUTION_LOOKBACK_MONTHS - 1).months).beginning_of_month
        income = ::CashTransaction.income_like.where(transaction_date: from..to).sum(:amount).to_f
        spend  = ::CashTransaction.spend_like.where(transaction_date: from..to).sum(:amount).to_f
        ((income + spend) / CONTRIBUTION_LOOKBACK_MONTHS).round(2).to_f
      end
    end
  end
end
