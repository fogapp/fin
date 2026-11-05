# typed: strict

module Api
  module Render
    module Concerns
      module MonthlySpend
        extend T::Sig

        # Groups any cash_transactions scope by month and returns { "YYYY-MM-DD" => Float }.
        # The caller is responsible for pre-filtering to the desired transaction types.
        # Sums are negated, not abs'd: spend is stored negative, and a month
        # where returns exceed charges should render as negative spend rather
        # than flipping sign.
        sig { params(scope: T.untyped).returns(T.untyped) }
        def monthly_spend(scope)
          scope
            .group_by_period(:month, :transaction_date)
            .sum(:amount)
            .transform_keys(&:to_s)
            .transform_values { |v| -v.to_f }
        end
      end
    end
  end
end
