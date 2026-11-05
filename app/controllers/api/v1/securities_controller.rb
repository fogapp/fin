# typed: true

module Api
  module V1
    class SecuritiesController < BaseController
      renders_with Api::Render::Security

      def index
        render_cached("market") { renderer.index }
      end

      def show
        # Same per-id key pattern as market_candles below; `from` windows the
        # price chart.
        render_cached("market_show:#{params[:id].to_s.upcase}", params: [ :from ]) do
          renderer.show
        end
      end

      # OHLCV history + corporate actions for the advanced chart. Global
      # data, but keyed per household like every cached endpoint — the TTL
      # bounds staleness from provider syncs (which bypass callbacks).
      def candles
        render_cached("market_candles:#{params[:id].to_s.upcase}", params: [ :range ]) do
          renderer.candles
        end
      end

      # Market overview: benchmark indices, movers among tracked
      # instruments, aggregated news.
      def summary
        render_cached("market_summary") do
          Api::Render::MarketSummary.new(params: params).show
        end
      end

      # Instrument classes addable through watch/search. Crypto is excluded:
      # those rows live under crypto_symbol and are priced via CoinGecko/CMC.
      WATCHABLE_CLASSES = [
        Instruments::InstrumentClass::Equity,
        Instruments::InstrumentClass::Etf,
        Instruments::InstrumentClass::MutualFund
      ].freeze

      def search
        results = Instruments::TickerSearch.new.call(params[:q].to_s)
        render json: { results: results }
      end

      def watch
        ticker   = params.require(:ticker).to_s.upcase.strip
        name     = params[:name].to_s.strip.presence || ticker
        # Deliberately not enum_param: an unrecognized class falls back to
        # equity (the historical contract) instead of 422ing the watch.
        klass    = Instruments::InstrumentClass.try_deserialize(params[:instrument_class].to_s)
        klass    = Instruments::InstrumentClass::Equity unless klass && WATCHABLE_CLASSES.include?(klass)
        # Resolver keys market watches on the ticker scheme; crypto rows live
        # under crypto_symbol and can never be adopted or duplicated here.
        security = Instruments::Resolver.resolve!(
          instrument_class: klass, ticker: ticker, name: name
        )
        SecurityWatch.find_or_create_by!(security: security, household: Current.household)

        # Fetch prices in the background through the instrument's candle
        # provider — new securities get full history, existing ones the
        # compact top-up. The company overview still comes from Alpha Vantage.
        if MarketData::Router.available_for?(security, MarketData::Capability::Candles)
          SyncSecurityPricesJob.perform_later(security.id)
        end
        if ::AlphaVantage.configured? && security.overview.blank?
          SyncSecurityOverviewJob.perform_later(security.id)
        end

        render json: { id: security.id, ticker: security.ticker, name: security.name, watched: true, syncing: true }
      end

      def unwatch
        security = Security.find_by!(ticker: params[:id].upcase)
        SecurityWatch.where(security: security, household: Current.household).destroy_all
        head :no_content
      end

      def news
        render json: Api::Render::Security.new(params: params).news
      end

      # The provider calls run in the background — same contract as watch,
      # whose "syncing" response the Market page already re-checks for. The
      # jobs own rate-limit retries, so the inline 429 path is gone.
      def refresh
        security = Security.find_by!(ticker: params[:id].upcase)
        prices_available = MarketData::Router.available_for?(security, MarketData::Capability::Candles)

        unless prices_available || ::AlphaVantage.configured?
          return render json: { error: "Market data provider not configured" }, status: :unprocessable_content
        end

        SyncSecurityPricesJob.perform_later(security.id) if prices_available
        if ::AlphaVantage.configured? && security.security_type != Security::CRYPTO_TYPE
          if security.overview.nil? || T.must(T.must(security.overview).fetched_at) < 24.hours.ago
            SyncSecurityOverviewJob.perform_later(security.id)
          end
        end

        render json: { status: "syncing", ticker: security.ticker, syncing: true }
      end
    end
  end
end
