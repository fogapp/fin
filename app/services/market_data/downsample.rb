# typed: strict

module MarketData
  # Bounds price-chart payloads the same way NetWorthHistory samples its
  # series: points inside the trailing daily window stay daily, older points
  # thin to one per week. Recent-period views (1M/6M/YTD/1Y) keep full
  # resolution; multi-year views get weekly resolution — visually identical
  # at chart scale, ~7x fewer rows.
  module Downsample
    extend T::Sig

    # Mirrors NetWorthHistory::DAILY_SAMPLING_LIMIT.
    DAILY_WINDOW_DAYS = 400

    # rows: ascending [Date, ...] tuples (date first). Keeps the last row of
    # each ISO week beyond the daily window, so the retained close is the
    # week's final trading day.
    sig { params(rows: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def self.weekly_beyond_window(rows)
      cutoff = Date.current - DAILY_WINDOW_DAYS
      older, recent = rows.partition { |row| row.first < cutoff }
      weekly = older.group_by { |row| [ row.first.cwyear, row.first.cweek ] }.values.map(&:last)
      weekly + recent
    end
  end
end
