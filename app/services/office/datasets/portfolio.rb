# typed: strict

module Office
  module Datasets
    # The consolidated portfolio: one row per security across accounts,
    # with each position's weight, followed by the performance block for
    # the window (TWR and XIRR) that the Investments page header shows.
    #
    # The two tables share a sheet, separated by a blank row — Office's CSV
    # import accepts ragged rows, and keeping them together means one
    # spreadsheet holds everything the page shows rather than two that have
    # to be refreshed in step.
    class Portfolio
      extend T::Sig

      HEADER = T.let(
        [
          "Ticker", "Name", "CUSIP", "Asset class", "Quantity", "Price", "Market value",
          "Weight %", "Cost basis", "Unrealized G/L", "Unrealized G/L %",
          "Est. annual income", "Dividend yield %"
        ].freeze,
        T::Array[String]
      )

      DEFAULT_WINDOW_DAYS = 365
      MAX_WINDOW_YEARS = 10

      sig { params(params: T::Hash[Symbol, T.untyped]).void }
      def initialize(params)
        @params = T.let(params, T::Hash[Symbol, T.untyped])
      end

      sig { returns(Grid) }
      def grid
        data      = Api::Render::Portfolio.new(params: {}).index
        positions = Array(data[:positions])
        summary   = data[:summary] || {}
        total     = summary[:total_value].to_f

        rows = T.let([ HEADER ], T::Array[T::Array[T.untyped]])
        positions.each { |p| rows << row(p, total) }
        rows.concat(totals_block(summary, data[:as_of_date]))
        rows.concat(performance_block)

        Grid.new(title: "Portfolio", rows: rows, filters: @params)
      end

      private

      sig { params(p: T::Hash[Symbol, T.untyped], total: Float).returns(T::Array[T.untyped]) }
      def row(p, total)
        market_value = p[:market_value].to_f
        [
          p[:security_ticker],
          p[:security_name],
          p[:security_cusip],
          p[:asset_class],
          p[:quantity].to_f,
          p[:price].to_f,
          market_value,
          total > 0 ? (market_value / total * 100).round(2) : nil,
          p[:cost_basis].to_f,
          p[:unrealized_gl].to_f,
          p[:unrealized_gl_pct].to_f,
          p[:est_annual_income].to_f,
          p[:dividend_yield].to_f
        ]
      end

      sig { params(summary: T::Hash[Symbol, T.untyped], as_of: T.untyped).returns(T::Array[T::Array[T.untyped]]) }
      def totals_block(summary, as_of)
        [
          [],
          [ "Totals" ],
          [ "As of", as_of ],
          [ "Market value", summary[:total_value].to_f ],
          [ "Cost basis", summary[:total_cost_basis].to_f ],
          [ "Unrealized G/L", summary[:unrealized_gl].to_f ],
          [ "Est. annual income", summary[:est_annual_income].to_f ]
        ]
      end

      sig { returns(T::Array[T::Array[T.untyped]]) }
      def performance_block
        perf = ::Valuation::PortfolioPerformance.call(from: from_date, to: to_date)
        [
          [],
          [ "Performance" ],
          [ "From", perf[:from] ],
          [ "To", perf[:to] ],
          [ "Start value", perf[:start_value] ],
          [ "End value", perf[:end_value] ],
          [ "Net external flows", perf[:net_external_flows] ],
          [ "TWR %", perf[:twr_pct] ],
          [ "TWR annualized %", perf[:twr_annualized_pct] ],
          # Nil below the 90-day window, where an annualized rate would be
          # extrapolated noise — the blank is the honest cell.
          [ "XIRR %", perf[:xirr_pct] ]
        ]
      end

      # Same clamping as GET /portfolio/performance: the series walks every
      # day in the window, so a decade is the ceiling.
      sig { returns(Date) }
      def from_date
        requested = @params[:from].present? ? Date.iso8601(@params[:from].to_s) : DEFAULT_WINDOW_DAYS.days.ago.to_date
        [ requested, MAX_WINDOW_YEARS.years.ago.to_date ].max
      end

      sig { returns(Date) }
      def to_date
        @params[:to].present? ? Date.iso8601(@params[:to].to_s) : Date.current
      end
    end
  end
end
