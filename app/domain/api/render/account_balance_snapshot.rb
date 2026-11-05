# typed: strict

module Api
  module Render
    # Daily balance series for an account's balance chart.
    class AccountBalanceSnapshot < Api::Render::Base
      extend T::Sig

      # Default window: the balance chart is a trend view — a year of daily
      # points is plenty, and unbounded history grew without limit. Clients
      # can widen with from/to (ISO dates; malformed input 400s via
      # Date::Error in the API base controller).
      DEFAULT_RANGE = T.let(1.year, ActiveSupport::Duration)

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        account = ::Account.find(params[:account_id])
        from = params[:from].present? ? Date.iso8601(params[:from]) : DEFAULT_RANGE.ago.to_date
        to   = params[:to].present? ? Date.iso8601(params[:to]) : nil
        ::AccountBalanceSnapshot.daily_series(account.id, from: from, to: to).map { |r|
          {
            date:             r.date.to_s,
            balance:          r.balance.to_f,
            balance_currency: r.balance_currency,
            balance_usd:      r.balance_usd&.to_f,
            source:           r.source
          }
        }
      end
    end
  end
end
