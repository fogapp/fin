# typed: strict

# Namespace for the market data platform (docs/instruments_platform_design.md).
# Constants live here so Zeitwerk loads them regardless of which service file
# is touched first.
module MarketData
  # Curated benchmarks kept fresh even when not held or watched. The sync
  # scheduler reads the tickers; the benchmarks endpoint and market summary
  # read the labels.
  BENCHMARKS = T.let([
    { symbol: "SPY", label: "S&P 500" },
    { symbol: "QQQ", label: "NASDAQ-100" },
    { symbol: "DIA", label: "Dow Jones" },
    { symbol: "IWM", label: "Russell 2000" }
  ].freeze, T::Array[T::Hash[Symbol, String]])

  BENCHMARK_TICKERS = T.let(BENCHMARKS.map { |b| b.fetch(:symbol) }.freeze, T::Array[String])
end
