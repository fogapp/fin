# typed: strict

module Api
  module Render
    # The market overview payload: benchmark indices strip, biggest movers
    # among the household's tracked (held or watched) instruments, and an
    # aggregated news feed across those instruments.
    class MarketSummary < Api::Render::Base
      extend T::Sig

      MOVERS_LIMIT = 5
      NEWS_LIMIT = 25

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        tracked = tracked_securities
        stats   = ::MarketData::DailyStats.call(tracked.map(&:id) + benchmark_securities.map(&:id))

        {
          as_of:   Date.current.to_s,
          indices: indices(stats),
          movers:  movers(tracked, stats),
          news:    news(tracked)
        }
      end

      private

      # Held (from the same resolver every holdings page uses) plus watched.
      sig { returns(T::Array[::Security]) }
      def tracked_securities
        held_ids    = ::Positions::CurrentPositions.new.relation.distinct.pluck(:security_id)
        watched_ids = ::SecurityWatch.pluck(:security_id)
        ::Security.where(id: (held_ids + watched_ids).uniq).to_a
      end

      sig { returns(T::Array[::Security]) }
      def benchmark_securities
        @benchmark_securities ||= T.let(
          ::Security.with_ticker.where(ticker: ::MarketData::BENCHMARK_TICKERS).to_a,
          T.nilable(T::Array[::Security])
        )
      end

      sig { params(stats: T::Hash[String, ::MarketData::DailyStats::Stat]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def indices(stats)
        labels = ::MarketData::BENCHMARKS.to_h { |b| [ b[:symbol], b[:label] ] }
        by_ticker = benchmark_securities.index_by(&:ticker)

        ::MarketData::BENCHMARK_TICKERS.filter_map do |ticker|
          security = by_ticker[ticker]
          next nil unless security

          stat = stats[security.id]
          {
            symbol:         ticker,
            label:          labels[ticker] || ticker,
            close:          stat&.last_close,
            date:           stat&.last_date&.to_s,
            day_change_pct: stat&.day_change_pct,
            spark:          stat&.spark || []
          }
        end
      end

      sig do
        params(tracked: T::Array[::Security], stats: T::Hash[String, ::MarketData::DailyStats::Stat])
          .returns(T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]])
      end
      def movers(tracked, stats)
        rows = tracked.filter_map do |s|
          stat = stats[s.id]
          next nil if stat&.day_change_pct.nil?

          {
            id:             s.id,
            param:          s.to_param,
            ticker:         s.ticker,
            name:           s.name,
            display_name:   s.display_name,
            instrument_class: s.instrument_class,
            close:          stat&.last_close,
            day_change_pct: stat&.day_change_pct,
            spark:          stat&.spark || []
          }
        end

        sorted = rows.sort_by { |r| -r[:day_change_pct] }
        {
          gainers: sorted.select { |r| r[:day_change_pct].positive? }.first(MOVERS_LIMIT),
          losers:  sorted.select { |r| r[:day_change_pct].negative? }.last(MOVERS_LIMIT).reverse
        }
      end

      sig { params(tracked: T::Array[::Security]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def news(tracked)
        by_id = tracked.index_by(&:id)
        ::SecurityNewsArticle
          .where(security_id: by_id.keys)
          .recent
          .limit(NEWS_LIMIT)
          .map do |a|
            security = by_id[a.security_id]
            {
              ticker:          security&.ticker,
              param:           security&.to_param,
              title:           a.title,
              url:             a.url,
              source:          a.source,
              published_at:    a.published_at&.strftime("%Y%m%dT%H%M%S"),
              summary:         a.summary,
              sentiment:       a.sentiment,
              sentiment_score: a.sentiment_score&.to_f
            }
          end
      end
    end
  end
end
