# typed: true

module Api
  module V1
    class BenchmarksController < BaseController
      # Symbols must stay within MarketData::BENCHMARKS so the sync
      # scheduler keeps them fresh.
      BENCHMARKS = MarketData::BENCHMARKS

      # GET /benchmarks — returns metadata list (no prices) for the suggestions dropdown
      def index
        render json: BENCHMARKS.map { |b| { symbol: b[:symbol], label: b[:label] } }
      end

      # Tickers are letters/digits with optional . or - separators — reject
      # arbitrary strings before they hit the identifier lookup.
      TICKER_FORMAT = /\A[A-Z0-9][A-Z0-9.\-]{0,9}\z/

      # GET /benchmarks/:symbol — returns price history for a known ticker.
      # Read-only: a GET must not create Security rows, so unknown tickers
      # get an empty payload instead of a resolver-created instrument.
      def show
        ticker = params[:symbol].upcase
        unless ticker.match?(TICKER_FORMAT)
          return render json: { error: "Invalid ticker symbol" }, status: :bad_request
        end

        label = BENCHMARKS.find { |b| b[:symbol] == ticker }&.dig(:label) || ticker
        render json: benchmark_payload(ticker, label)
      end

      private

      def benchmark_payload(ticker, label)
        # Non-creating lookup on the ticker scheme (the resolver's read path).
        # Benchmark instruments come from watch/sync flows or the curated
        # scheduler list — never from this GET.
        security = Instruments::Resolver.find_by_identifier(InstrumentIdentifier::Scheme::Ticker, ticker)
        return { symbol: ticker, label: label, prices: [], syncing: false } if security.nil?

        closes = MarketData::PriceSeries.daily_closes(security)
        if closes.empty? && MarketData::Router.available_for?(security, MarketData::Capability::Candles)
          SyncSecurityPricesJob.perform_later(security.id)
        end

        prices = MarketData::Downsample
          .weekly_beyond_window(closes)
          .map { |d, c| [ d.to_s, c.to_f ] }

        { symbol: ticker, label: label, prices: prices, syncing: prices.empty? }
      end
    end
  end
end
