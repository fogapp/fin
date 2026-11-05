# typed: strict

module Api
  module Render
    class Security < Api::Render::Base
      extend T::Sig

      include Concerns::SerializesInvestmentTransaction

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        positions   = ::Positions::CurrentPositions.new.relation.group(:security_id).sum(:market_value)
        ytd_from    = Date.current.beginning_of_year
        watched_ids = SecurityWatch.pluck(:security_id).to_set # HouseholdScoped => current household

        securities  = household_securities.order(:ticker, :name).to_a
        ids         = securities.map(&:id)

        # Batched DISTINCT ON reads instead of per-security lookups. Adjusted
        # closes, so a split inside the year can't fake a YTD crash.
        quotes = InstrumentQuote.where(security_id: ids).index_by(&:security_id)
        latest_closes     = ::MarketData::PriceSeries.edge_closes_by_security(ids)
        year_start_closes = ::MarketData::PriceSeries.edge_closes_by_security(ids, on_or_after: ytd_from)

        daily_stats = ::MarketData::DailyStats.call(ids)

        securities.map do |s|
          latest_date, latest_close = latest_closes[s.id]
          year_start_price = year_start_closes[s.id]&.last

          ytd_change = if latest_close && year_start_price && year_start_price > 0
            ((latest_close.to_f - year_start_price.to_f) / year_start_price.to_f * 100).round(2)
          end

          quote = quotes[s.id]
          price_payload = if quote
            { date: quote.as_of.to_date.to_s, close: quote.price.to_f,
              source: quote.source, age_days: ((Time.current - quote.as_of) / 1.day).floor }
          elsif latest_date && latest_close
            { date: latest_date.to_s, close: latest_close.to_f,
              source: "eod", age_days: (Date.current - latest_date).to_i }
          end

          stat = daily_stats[s.id]
          serialize(s).merge(
            latest_price:     price_payload,
            instrument_class: s.instrument_class,
            ytd_change_pct:   ytd_change,
            day_change_pct:   stat&.day_change_pct,
            spark:            stat&.spark || [],
            market_value:     positions[s.id].to_f.round(2),
            watched:          watched_ids.include?(s.id)
          )
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        security  = ::Security.find_by_param!(params[:id])
        ytd_from  = Date.current.beginning_of_year
        year_from = 1.year.ago.to_date
        dividends = security.investment_transactions.dividends

        # Current position across accounts — same resolver as every other
        # page, so the security page can no longer disagree with the
        # portfolio.
        positions = ::Positions::CurrentPositions.new.relation
                                                 .where(security_id: security.id)
                                                 .includes(:account).to_a
        as_of     = positions.map(&:as_of_date).max
        position  = if positions.any?
          mval       = positions.sum { |p| p.market_value.to_f }.round(2)
          snap_cost  = positions.sum { |p| (p.cost_basis_override || p.cost_basis).to_f }.round(2)
          held_qty   = positions.sum { |p| p.quantity.to_f }
          cost_basis = ::Positions::ResolvedCostBasis.new([ security.id ])
                         .resolve(security.id, quantity: held_qty, snapshot_cost_basis: snap_cost)
                         .cost_basis.round(2)
          unrealized = (mval - cost_basis).round(2)
          {
            as_of_date:    as_of,
            quantity:      positions.sum { |p| p.quantity.to_f }.round(4),
            market_value:  mval,
            cost_basis:    cost_basis,
            unrealized_gl: unrealized,
            by_account:    positions.map { |p| { account: p.account.name, quantity: p.quantity.to_f, market_value: p.market_value.to_f } }
          }
        end

        serialize(security).merge(
          price_chart:   price_chart(security),
          latest_price:  latest_price(security),
          position:      position,
          dividends: {
            lifetime: dividends.sum(:income_usd).to_f,
            ytd:      dividends.where(trade_date: ytd_from..).sum(:income_usd).to_f,
            last_12mo: dividends.where(trade_date: year_from..).sum(:income_usd).to_f
          },
          watched:             security.watched_by?(Current.household),
          overview:            security.security_type == ::Security::CRYPTO_TYPE ? nil : serialize_overview(security.overview),
          recent_transactions: recent_for(security.investment_transactions)
        )
      end

      # Chart ranges the candles endpoint accepts. 5Y/MAX serve weekly
      # candles (a decade of dailies is ~2,500 rows for no visual gain);
      # everything else serves the daily rows the store already holds.
      CANDLE_RANGES = T.let({
        "1m"  => -> { Date.current - 1.month },
        "3m"  => -> { Date.current - 3.months },
        "6m"  => -> { Date.current - 6.months },
        "ytd" => -> { Date.current.beginning_of_year },
        "1y"  => -> { Date.current - 1.year },
        "5y"  => -> { Date.current - 5.years },
        "max" => -> { }
      }.freeze, T::Hash[String, T.proc.returns(T.nilable(Date))])

      WEEKLY_RANGES = T.let([ "5y", "max" ].freeze, T::Array[String])

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def candles
        security = ::Security.find_by_param!(params[:id])
        range    = CANDLE_RANGES.key?(params[:range].to_s) ? params[:range].to_s : "1y"
        from     = T.must(CANDLE_RANGES[range]).call

        rows = ::MarketData::OhlcvSeries.rows(security, from: from)
        granularity = ::Candle::GRANULARITY_DAILY
        if WEEKLY_RANGES.include?(range)
          rows = ::MarketData::OhlcvSeries.weekly(rows)
          granularity = ::MarketData::OhlcvSeries::GRANULARITY_WEEKLY
        end

        # Baseline for "change over this range": the last close before the
        # window. A generous staleness window — the point is the nearest
        # prior close, not a fresh one.
        prev_close = from && ::MarketData::PriceSeries.close_on(security, from - 1, max_staleness_days: 60)

        events = ::CorporateAction
          .where(security_id: security.id)
          .where(from ? { ex_date: from.. } : {})
          .order(:ex_date)
          .map { |a|
            { kind: a.kind, date: a.ex_date.to_s, ratio: a.ratio&.to_f, amount: a.amount&.to_f }
          }

        {
          id:           security.id,
          ticker:       security.ticker,
          range:        range,
          granularity:  granularity,
          prev_close:   prev_close&.to_f,
          latest_price: latest_price(security),
          candles:      rows.map { |r| { t: r.date.to_s, o: r.open, h: r.high, l: r.low, c: r.close, v: r.volume } },
          events:       events
        }
      end

      # GET /securities/:ticker/news — the 50 most recent stored articles.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def news
        security = ::Security.find_by!(ticker: params[:id].to_s.upcase)
        security.news_articles.recent.limit(50).map { |a|
          {
            title:           a.title,
            url:             a.url,
            source:          a.source,
            published_at:    a.published_at&.strftime("%Y%m%dT%H%M%S"),
            summary:         a.summary,
            sentiment:       a.sentiment,
            sentiment_score: a.sentiment_score&.to_f
          }
        }
      end

      sig { params(security: ::Security).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(security)
        {
          id:               security.id,
          ticker:           security.ticker,
          name:             security.name,
          cusip:            security.cusip,
          security_type:    security.security_type,
          instrument_class: security.instrument_class,
          display_name:  security.display_name,
          slug:          security.slug
        }
      end

      private

      # Securities carry no household_id, so the market list is the ones this
      # household holds (ledger or snapshots), watches, or benchmarks against
      # — the same scoping search uses. Listing every row in the table would
      # show (and price) other households' holdings. EXISTS subqueries keep
      # HouseholdScoped's default_scope on each side.
      sig { returns(T.untyped) }
      def household_securities
        traded   = InvestmentTransaction.where("investment_transactions.security_id = securities.id")
        snapshot = PositionSnapshot.where("position_snapshots.security_id = securities.id")
        watched  = SecurityWatch.where("security_watches.security_id = securities.id")

        ::Security.where(traded.arel.exists)
                  .or(::Security.where(snapshot.arel.exists))
                  .or(::Security.where(watched.arel.exists))
                  .or(::Security.where(ticker: ::MarketData::BENCHMARK_TICKERS))
      end

      # Optional ?from= windows the query; either way the payload is
      # downsampled to weekly beyond the trailing daily window so a decade of
      # daily closes can't ship 5k+ rows. The security page slices periods
      # client-side (1M..1Y stay within the daily window and are unaffected;
      # 5Y/MAX render from weekly points).
      sig { params(security: ::Security).returns(T.untyped) }
      def price_chart(security)
        rows = ::MarketData::OhlcvSeries.rows(security, from: date_param(:from))
                                        .map { |row| [ row.date, row.close, row.volume ] }
        MarketData::Downsample.weekly_beyond_window(rows)
                              .map { |d, c, v| [ d.to_s, c.to_f, v.to_i ] }
      end

      sig { params(ov: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def serialize_overview(ov)
        return nil unless ov
        {
          sector:               ov.sector,
          industry:             ov.industry,
          exchange:             ov.exchange,
          country:              ov.country,
          description:          ov.description,
          market_cap:           ov.market_cap,
          pe_ratio:             ov.pe_ratio&.to_f,
          forward_pe:           ov.forward_pe&.to_f,
          eps:                  ov.eps&.to_f,
          beta:                 ov.beta&.to_f,
          dividend_yield:       ov.dividend_yield&.to_f,
          dividend_per_share:   ov.dividend_per_share&.to_f,
          week_52_high:         ov.week_52_high&.to_f,
          week_52_low:          ov.week_52_low&.to_f,
          analyst_target_price: ov.analyst_target_price&.to_f,
          profit_margin:        ov.profit_margin&.to_f,
          return_on_equity:     ov.return_on_equity&.to_f,
          revenue_ttm:          ov.revenue_ttm,
          shares_outstanding:   ov.shares_outstanding,
          ex_dividend_date:     ov.ex_dividend_date&.to_s,
          fetched_at:           ov.fetched_at&.iso8601
        }
      end

      sig { params(security: ::Security).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_price(security)
        spot = ::MarketData::PriceSeries.latest_quote(security)
        return nil unless spot

        { date: spot.as_of.to_date.to_s, close: spot.price.to_f,
          source: spot.source, age_days: spot.age_days }
      end
    end
  end
end
