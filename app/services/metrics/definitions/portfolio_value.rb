# typed: strict

module Metrics
  module Definitions
    # Total portfolio market value per day — the same series the Portfolio
    # page, dashboard and net worth use (Valuation::PortfolioSeries), so the
    # stat page and the charts it links from tell the same story.
    class PortfolioValue < Definition
      key :portfolio_value
      label "Portfolio value"
      description "Total market value of investment holdings, tracked daily."
      unit Unit::Currency
      granularity Granularity::Day
      value_type ValueType::Level
      direction Direction::UpGood
      group Group::Investments

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        ::Valuation::PortfolioSeries.call(from: from, to: to)
          .each_with_object({}) do |(date, value), out|
            d = date.to_date
            out[d] = value.to_f.round(2) if d.between?(from, to)
          end
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::PositionSnapshot.minimum(:as_of_date)
      end
    end
  end
end
