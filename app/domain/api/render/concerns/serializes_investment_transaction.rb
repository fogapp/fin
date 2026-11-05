# typed: strict

module Api
  module Render
    module Concerns
      module SerializesInvestmentTransaction
        extend T::Sig

        sig { params(txn: ::InvestmentTransaction).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_transaction(txn)
          {
            id:               txn.id,
            trade_date:       txn.trade_date,
            description:      txn.description,
            quantity:         txn.quantity.to_f,
            price_usd:        txn.price_usd.to_f,
            amount_usd:       txn.amount_usd.to_f,
            cost_usd:         txn.cost_usd.to_f,
            income_usd:       txn.income_usd.to_f,
            gl_short_usd:     txn.gl_short_usd.to_f,
            gl_long_usd:      txn.gl_long_usd.to_f,
            account_id:       txn.account_id,
            account_name:     T.must(txn.account).name,
            security_id:      txn.security_id,
            security_ticker:  txn.security&.ticker,
            security_name:    txn.security&.name,
            transaction_type:          T.must(txn.transaction_type).code_description,
            transaction_type_category: T.must(txn.transaction_type).category
          }
        end

        TOP_N = 10

        # Narrows a scope to a trade-date window; either end may be open.
        sig { params(scope: T.untyped, from: T.nilable(Date), to: T.nilable(Date)).returns(T.untyped) }
        def in_window(scope, from, to)
          scope = scope.where(trade_date: from..) if from
          scope = scope.where(trade_date: ..to) if to
          scope
        end

        sig { params(scope: T.untyped, value_expr: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def top_securities_for(scope, value_expr)
          scope
            .joins(:security)
            .group("securities.id", "securities.ticker", "securities.name")
            .order(Arel.sql("#{value_expr} DESC"))
            .limit(TOP_N)
            .pluck("securities.ticker", "securities.name", Arel.sql(value_expr), Arel.sql("COUNT(*)"))
            .map { |ticker, name, total, count|
              { ticker: ticker, name: name, total: total.to_f.round(2), count: count }
            }
        end

        sig { params(scope: T.untyped, value_expr: String).returns(T::Hash[String, Float]) }
        def by_account_for(scope, value_expr)
          scope
            .joins(:account)
            .group("accounts.id", "accounts.name")
            .order(Arel.sql("#{value_expr} DESC"))
            .pluck("accounts.name", Arel.sql(value_expr))
            .to_h
            .transform_values { |v| v.to_f.round(2) }
        end

        sig { params(scope: T.untyped, value_expr: T.untyped).returns(T.untyped) }
        def monthly_series_for(scope, value_expr)
          scope
            .group_by_period(:month, :trade_date)
            .sum(Arel.sql(value_expr))
            .sort
            .map { |date, v| [ date.to_s, v.to_f.round(2) ] }
        end

        # `from` trims the returned points without resetting the running total,
        # so a windowed chart still reads "cumulative to date" — pass a scope
        # bounded only at its end.
        sig { params(scope: T.untyped, value_expr: String, from: T.nilable(Date)).returns(T.untyped) }
        def cumulative_series_for(scope, value_expr, from: nil)
          running = 0.0
          points = scope
            .group_by_period(:day, :trade_date)
            .sum(Arel.sql(value_expr))
            .sort
            .map { |date, v| running += v.to_f; [ date, running.round(2) ] }

          # The running total accumulates over every day, but each retained
          # point already carries the cumulative value — so thinning old
          # points to weekly (same policy as the price charts) loses nothing
          # visually while a decade of activity stops shipping thousands of
          # rows.
          points = points.reject { |date, _| date < from } if from
          MarketData::Downsample.weekly_beyond_window(points).map { |date, v| [ date.to_s, v ] }
        end

        sig { params(scope: T.untyped, limit: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def recent_for(scope, limit: 50)
          all_for(scope, limit: limit)
        end

        # Default generous enough that the investment pages (which paginate
        # and search client-side over this array) keep their current feel;
        # totals.count still reports the full count, so clients can page
        # further with limit/offset.
        DEFAULT_TRANSACTION_LIMIT = 500
        MAX_TRANSACTION_LIMIT     = 2_000

        # Windowed serialization driven by limit/offset request params — the
        # same opt-in contract cash transactions use, but with a server-side
        # default so an index can never serialize the entire history.
        sig { params(scope: T.untyped, request_params: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def windowed_for(scope, request_params)
          limit, offset = Paginated.window(request_params, default: DEFAULT_TRANSACTION_LIMIT, max: MAX_TRANSACTION_LIMIT)
          all_for(scope, limit: limit, offset: offset)
        end

        sig { params(scope: T.untyped, limit: T.nilable(Integer), offset: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def all_for(scope, limit: nil, offset: 0)
          q = scope.includes(:security, :account, :transaction_type).order(trade_date: :desc, id: :desc)
          q = q.offset(offset) if offset.positive?
          q = q.limit(limit) if limit
          q.map { |t| serialize_transaction(t) }
        end
      end
    end
  end
end
