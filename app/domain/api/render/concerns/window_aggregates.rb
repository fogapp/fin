# typed: strict

module Api
  module Render
    module Concerns
      module WindowAggregates
        extend T::Sig

        # One aggregate per date window over the same cash_transactions
        # scope, in a single scan (SUM(...) FILTER (WHERE ...)) rather than
        # one query per window. Returns the raw values in `windows` order;
        # an empty window yields 0. Endless ranges (ytd_from..) are allowed.
        # Sums cash_transactions.amount, or counts rows with count: true.
        # Built from Arel nodes, so the window bounds are quoted values.
        sig do
          params(scope: T.untyped, windows: T::Array[T::Range[T.untyped]], count: T::Boolean)
            .returns(T::Array[T.untyped])
        end
        def window_aggregates(scope, windows, count: false)
          table = ::CashTransaction.arel_table
          columns = windows.map do |range|
            aggregate = count ? Arel.star.count : table[:amount].sum
            Arel::Nodes::NamedFunction.new(
              "COALESCE", [ aggregate.filter(table[:transaction_date].between(range)), Arel::Nodes.build_quoted(0) ]
            )
          end

          # Bound the scan to the earliest window so the date index still helps.
          earliest = windows.map(&:begin).min
          Array.wrap(scope.where(transaction_date: earliest..).pick(*columns))
        end
      end
    end
  end
end
